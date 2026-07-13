# frozen_string_literal: true

require "spec_helper"

module OutlineExtractorFakes
  # Lightweight fakes for the table-shaped objects OutlineExtractor
  # consumes. These are real Ruby objects with the same surface the
  # extractor calls into — no mock framework methods, no stubs that
  # bypass the type system.
  class FakeFont
    attr_reader :tables

    def initialize(tables = {})
      @tables = tables
    end

    def table(tag)
      tables[tag]
    end

    def has_table?(tag)
      tables.key?(tag)
    end
  end

  FakeMaxp = Struct.new(:num_glyphs, keyword_init: true)

  FakeLoca = Struct.new(:parsed_flag, keyword_init: true) do
    def parsed?
      parsed_flag
    end
  end

  FakeHead = Struct.new(:index_to_loc_format, keyword_init: true)

  FakeGlyf = Struct.new(:glyphs_by_id, keyword_init: true) do
    def glyph_for(id, _loca, _head)
      glyphs_by_id[id]
    end
  end

  FakeSimpleGlyph = Struct.new(:glyph_id, :num_contours, :x_min, :y_min,
                               :x_max, :y_max, :contours, keyword_init: true) do
    def simple? = true
    def compound? = false
    def empty? = contours.empty?

    def points_for_contour(idx)
      contours[idx]
    end
  end

  FakeCompoundGlyph = Struct.new(:glyph_id, :components, :x_min, :y_min,
                                 :x_max, :y_max, keyword_init: true) do
    def simple? = false
    def compound? = true
    def empty? = components.empty?
  end

  FakeComponent = Struct.new(:glyph_index, :transformation_matrix)

  FakeCff = Struct.new(:charstrings_by_id, keyword_init: true) do
    def charstring_for_glyph(id)
      charstrings_by_id[id]
    end
  end

  FakeCharstring = Struct.new(:path, :bounding_box, keyword_init: true)
end

RSpec.describe Fontisan::OutlineExtractor do
  let(:num_glyphs) { 100 }
  let(:maxp) { OutlineExtractorFakes::FakeMaxp.new(num_glyphs: num_glyphs) }

  describe "#initialize" do
    it "creates an extractor with a valid font" do
      font = OutlineExtractorFakes::FakeFont.new("maxp" => maxp)
      extractor = described_class.new(font)
      expect(extractor.font).to eq(font)
    end

    it "raises ArgumentError for nil font" do
      expect do
        described_class.new(nil)
      end.to raise_error(ArgumentError, /cannot be nil/)
    end

    it "accepts any non-nil font" do
      non_nil = Object.new
      expect(described_class.new(non_nil).font).to eq(non_nil)
    end
  end

  describe "#extract" do
    let(:font) { OutlineExtractorFakes::FakeFont.new("maxp" => maxp) }
    let(:extractor) { described_class.new(font) }

    context "with invalid glyph_id" do
      it "raises ArgumentError for nil glyph_id" do
        expect do
          extractor.extract(nil)
        end.to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises ArgumentError for negative glyph_id" do
        expect do
          extractor.extract(-1)
        end.to raise_error(ArgumentError, /must be >= 0/)
      end

      it "raises ArgumentError for glyph_id exceeding num_glyphs" do
        expect { extractor.extract(100) }.to raise_error(
          ArgumentError,
          /exceeds number of glyphs/,
        )
      end
    end

    context "with TrueType font" do
      let(:loca) { OutlineExtractorFakes::FakeLoca.new(parsed_flag: true) }
      let(:head) { OutlineExtractorFakes::FakeHead.new(index_to_loc_format: 0) }
      let(:glyf) { OutlineExtractorFakes::FakeGlyf.new(glyphs_by_id: {}) }

      before do
        font.tables["glyf"] = glyf
        font.tables["loca"] = loca
        font.tables["head"] = head
      end

      it "extracts a simple glyph outline" do
        simple_glyph = OutlineExtractorFakes::FakeSimpleGlyph.new(
          glyph_id: 65, num_contours: 1,
          x_min: 100, y_min: 0, x_max: 300, y_max: 700,
          contours: [[
            { x: 100, y: 0, on_curve: true },
            { x: 200, y: 700, on_curve: true },
            { x: 300, y: 0, on_curve: true },
          ]]
        )
        glyf.glyphs_by_id[65] = simple_glyph

        outline = extractor.extract(65)

        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
        expect(outline.glyph_id).to eq(65)
        expect(outline.contour_count).to eq(1)
        expect(outline.point_count).to eq(3)
        expect(outline.bbox[:x_min]).to eq(100)
        expect(outline.bbox[:x_max]).to eq(300)
      end

      it "returns nil for empty glyphs" do
        empty_glyph = OutlineExtractorFakes::FakeSimpleGlyph.new(
          glyph_id: 32, num_contours: 0,
          x_min: 0, y_min: 0, x_max: 0, y_max: 0,
          contours: []
        )
        glyf.glyphs_by_id[32] = empty_glyph

        expect(extractor.extract(32)).to be_nil
      end

      it "returns nil when glyph is nil" do
        glyf.glyphs_by_id[0] = nil

        expect(extractor.extract(0)).to be_nil
      end

      it "raises MissingTableError when glyf table is missing" do
        font.tables.delete("glyf")

        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /glyf/,
        )
      end

      it "raises MissingTableError when loca table is missing" do
        font.tables.delete("loca")

        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /loca/,
        )
      end

      it "raises MissingTableError when head table is missing" do
        font.tables.delete("head")

        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /head/,
        )
      end

      context "with compound glyphs" do
        it "extracts compound glyph by resolving components" do
          component_glyph = OutlineExtractorFakes::FakeSimpleGlyph.new(
            glyph_id: 66, num_contours: 1,
            x_min: 0, y_min: 0, x_max: 100, y_max: 100,
            contours: [[
              { x: 0, y: 0, on_curve: true },
              { x: 100, y: 100, on_curve: true },
            ]]
          )
          component = OutlineExtractorFakes::FakeComponent.new(66, [1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
          compound_glyph = OutlineExtractorFakes::FakeCompoundGlyph.new(
            glyph_id: 65, components: [component],
            x_min: 0, y_min: 0, x_max: 100, y_max: 100
          )
          glyf.glyphs_by_id[65] = compound_glyph
          glyf.glyphs_by_id[66] = component_glyph

          outline = extractor.extract(65)

          expect(outline).to be_a(Fontisan::Models::GlyphOutline)
          expect(outline.glyph_id).to eq(65)
          expect(outline.contour_count).to be >= 1
        end

        it "applies transformations to component outlines" do
          scaled_component = OutlineExtractorFakes::FakeComponent.new(66, [2.0, 0.0, 0.0, 2.0, 10.0, 20.0])
          component_glyph = OutlineExtractorFakes::FakeSimpleGlyph.new(
            glyph_id: 66, num_contours: 1,
            x_min: 0, y_min: 0, x_max: 50, y_max: 50,
            contours: [[
              { x: 0, y: 0, on_curve: true },
              { x: 50, y: 50, on_curve: true },
            ]]
          )
          compound_glyph = OutlineExtractorFakes::FakeCompoundGlyph.new(
            glyph_id: 65, components: [scaled_component],
            x_min: 10, y_min: 20, x_max: 110, y_max: 120
          )
          glyf.glyphs_by_id[65] = compound_glyph
          glyf.glyphs_by_id[66] = component_glyph

          outline = extractor.extract(65)

          expect(outline).to be_a(Fontisan::Models::GlyphOutline)
          first_point = outline.points.first
          expect(first_point[:x]).to eq(10) # 0*2 + 10
          expect(first_point[:y]).to eq(20) # 0*2 + 20
        end
      end
    end

    context "with CFF font" do
      let(:cff) { OutlineExtractorFakes::FakeCff.new(charstrings_by_id: {}) }

      before do
        font.tables["CFF "] = cff
        font.tables.delete("glyf") if font.tables.key?("glyf")
      end

      it "extracts CFF glyph outline" do
        cff.charstrings_by_id[65] = OutlineExtractorFakes::FakeCharstring.new(
          path: [
            { type: :move_to, x: 100.0, y: 0.0 },
            { type: :line_to, x: 200.0, y: 700.0 },
            { type: :line_to, x: 300.0, y: 0.0 },
          ],
          bounding_box: [100.0, 0.0, 300.0, 700.0],
        )

        outline = extractor.extract(65)

        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
        expect(outline.glyph_id).to eq(65)
        expect(outline.contour_count).to be >= 1
        expect(outline.point_count).to be >= 3
      end

      it "returns nil for empty CFF glyphs" do
        cff.charstrings_by_id[32] = OutlineExtractorFakes::FakeCharstring.new(path: [], bounding_box: nil)

        expect(extractor.extract(32)).to be_nil
      end

      it "returns nil when charstring is nil" do
        cff.charstrings_by_id[0] = nil

        expect(extractor.extract(0)).to be_nil
      end

      it "handles CFF curve commands" do
        cff.charstrings_by_id[65] = OutlineExtractorFakes::FakeCharstring.new(
          path: [
            { type: :move_to, x: 100.0, y: 0.0 },
            { type: :curve_to, x1: 120.0, y1: 50.0, x2: 180.0, y2: 50.0,
              x: 200.0, y: 0.0 },
          ],
          bounding_box: [100.0, 0.0, 200.0, 50.0],
        )

        outline = extractor.extract(65)

        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
        expect(outline.point_count).to be >= 2
      end

      it "raises MissingTableError when CFF table is missing" do
        font.tables.delete("CFF ")

        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /CFF/,
        )
      end
    end

    context "with neither glyf nor CFF table" do
      it "raises MissingTableError" do
        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /neither glyf nor CFF/,
        )
      end
    end
  end
end
