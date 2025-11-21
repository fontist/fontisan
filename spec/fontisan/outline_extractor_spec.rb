# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::OutlineExtractor do
  describe "#initialize" do
    it "creates an extractor with a valid font" do
      font = instance_double(Fontisan::TrueTypeFont)
      allow(font).to receive(:respond_to?).with(:table).and_return(true)

      extractor = described_class.new(font)

      expect(extractor.font).to eq(font)
    end

    it "raises ArgumentError for nil font" do
      expect do
        described_class.new(nil)
      end.to raise_error(ArgumentError, /cannot be nil/)
    end

    it "raises ArgumentError for font without table method" do
      invalid_font = Object.new

      expect { described_class.new(invalid_font) }.to raise_error(
        ArgumentError,
        /must respond to :table/,
      )
    end
  end

  describe "#extract" do
    let(:font) { instance_double(Fontisan::TrueTypeFont) }
    let(:extractor) { described_class.new(font) }
    let(:maxp) { double("Maxp", num_glyphs: 100) }

    before do
      allow(font).to receive(:respond_to?).with(:table).and_return(true)
      allow(font).to receive(:table).with("maxp").and_return(maxp)
    end

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
      let(:glyf) { double("Glyf") }
      let(:loca) { double("Loca", parsed?: true) }
      let(:head) { double("Head", index_to_loc_format: 0) }

      before do
        allow(font).to receive(:has_table?).with("glyf").and_return(true)
        allow(font).to receive(:has_table?).with(Fontisan::Constants::CFF_TAG).and_return(false)
        allow(font).to receive(:table).with("glyf").and_return(glyf)
        allow(font).to receive(:table).with("loca").and_return(loca)
        allow(font).to receive(:table).with("head").and_return(head)
        allow(font).to receive(:table).with(Fontisan::Constants::CFF_TAG).and_return(nil)
      end

      it "extracts a simple glyph outline" do
        simple_glyph = double(
          "SimpleGlyph",
          glyph_id: 65,
          simple?: true,
          compound?: false,
          empty?: false,
          num_contours: 1,
          x_min: 100,
          y_min: 0,
          x_max: 300,
          y_max: 700,
        )

        allow(simple_glyph).to receive(:points_for_contour).with(0).and_return([
                                                                                 {
                                                                                   x: 100, y: 0, on_curve: true
                                                                                 },
                                                                                 {
                                                                                   x: 200, y: 700, on_curve: true
                                                                                 },
                                                                                 {
                                                                                   x: 300, y: 0, on_curve: true
                                                                                 },
                                                                               ])

        allow(glyf).to receive(:glyph_for).with(65, loca,
                                                head).and_return(simple_glyph)

        outline = extractor.extract(65)

        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
        expect(outline.glyph_id).to eq(65)
        expect(outline.contour_count).to eq(1)
        expect(outline.point_count).to eq(3)
        expect(outline.bbox[:x_min]).to eq(100)
        expect(outline.bbox[:x_max]).to eq(300)
      end

      it "returns nil for empty glyphs" do
        empty_glyph = double(
          "SimpleGlyph",
          empty?: true,
        )

        allow(glyf).to receive(:glyph_for).with(32, loca,
                                                head).and_return(empty_glyph)

        outline = extractor.extract(32)

        expect(outline).to be_nil
      end

      it "returns nil when glyph is nil" do
        allow(glyf).to receive(:glyph_for).with(0, loca, head).and_return(nil)

        outline = extractor.extract(0)

        expect(outline).to be_nil
      end

      it "raises MissingTableError when glyf table is missing" do
        allow(font).to receive(:table).with("glyf").and_return(nil)

        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /glyf/,
        )
      end

      it "raises MissingTableError when loca table is missing" do
        allow(font).to receive(:table).with("loca").and_return(nil)

        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /loca/,
        )
      end

      it "raises MissingTableError when head table is missing" do
        allow(font).to receive(:table).with("head").and_return(nil)

        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /head/,
        )
      end

      context "with compound glyphs" do
        let(:component) do
          double(
            "Component",
            glyph_index: 66,
            transformation_matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
          )
        end

        it "extracts compound glyph by resolving components" do
          # Component glyph (simple)
          component_glyph = double(
            "SimpleGlyph",
            glyph_id: 66,
            simple?: true,
            compound?: false,
            empty?: false,
            num_contours: 1,
            x_min: 0,
            y_min: 0,
            x_max: 100,
            y_max: 100,
          )

          allow(component_glyph).to receive(:points_for_contour).with(0).and_return([
                                                                                      {
                                                                                        x: 0, y: 0, on_curve: true
                                                                                      },
                                                                                      {
                                                                                        x: 100, y: 100, on_curve: true
                                                                                      },
                                                                                    ])

          # Compound glyph
          compound_glyph = double(
            "CompoundGlyph",
            glyph_id: 65,
            simple?: false,
            compound?: true,
            empty?: false,
            components: [component],
            x_min: 0,
            y_min: 0,
            x_max: 100,
            y_max: 100,
          )

          allow(glyf).to receive(:glyph_for).with(65, loca,
                                                  head).and_return(compound_glyph)
          allow(glyf).to receive(:glyph_for).with(66, loca,
                                                  head).and_return(component_glyph)

          outline = extractor.extract(65)

          expect(outline).to be_a(Fontisan::Models::GlyphOutline)
          expect(outline.glyph_id).to eq(65)
          expect(outline.contour_count).to be >= 1
        end

        it "applies transformations to component outlines" do
          # Component with scaling transformation
          scaled_component = double(
            "Component",
            glyph_index: 66,
            transformation_matrix: [2.0, 0.0, 0.0, 2.0, 10.0, 20.0], # scale 2x + offset
          )

          component_glyph = double(
            "SimpleGlyph",
            glyph_id: 66,
            simple?: true,
            compound?: false,
            empty?: false,
            num_contours: 1,
            x_min: 0,
            y_min: 0,
            x_max: 50,
            y_max: 50,
          )

          allow(component_glyph).to receive(:points_for_contour).with(0).and_return([
                                                                                      {
                                                                                        x: 0, y: 0, on_curve: true
                                                                                      },
                                                                                      {
                                                                                        x: 50, y: 50, on_curve: true
                                                                                      },
                                                                                    ])

          compound_glyph = double(
            "CompoundGlyph",
            glyph_id: 65,
            simple?: false,
            compound?: true,
            empty?: false,
            components: [scaled_component],
            x_min: 10,
            y_min: 20,
            x_max: 110,
            y_max: 120,
          )

          allow(glyf).to receive(:glyph_for).with(65, loca,
                                                  head).and_return(compound_glyph)
          allow(glyf).to receive(:glyph_for).with(66, loca,
                                                  head).and_return(component_glyph)

          outline = extractor.extract(65)

          expect(outline).to be_a(Fontisan::Models::GlyphOutline)
          # Check that transformation was applied
          first_point = outline.points.first
          expect(first_point[:x]).to eq(10) # 0*2 + 10
          expect(first_point[:y]).to eq(20) # 0*2 + 20
        end
      end
    end

    context "with CFF font" do
      let(:cff) { double("Cff") }
      let(:charstring) do
        double(
          "Charstring",
          path: [
            { type: :move_to, x: 100.0, y: 0.0 },
            { type: :line_to, x: 200.0, y: 700.0 },
            { type: :line_to, x: 300.0, y: 0.0 },
          ],
          bounding_box: [100.0, 0.0, 300.0, 700.0],
        )
      end

      before do
        allow(font).to receive(:has_table?).with("glyf").and_return(false)
        allow(font).to receive(:has_table?).with(Fontisan::Constants::CFF_TAG).and_return(true)
        allow(font).to receive(:table).with(Fontisan::Constants::CFF_TAG).and_return(cff)
        allow(font).to receive(:table).with("glyf").and_return(nil)
      end

      it "extracts CFF glyph outline" do
        allow(cff).to receive(:charstring_for_glyph).with(65).and_return(charstring)

        outline = extractor.extract(65)

        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
        expect(outline.glyph_id).to eq(65)
        expect(outline.contour_count).to be >= 1
        expect(outline.point_count).to be >= 3
      end

      it "returns nil for empty CFF glyphs" do
        empty_charstring = double("Charstring", path: [])
        allow(cff).to receive(:charstring_for_glyph).with(32).and_return(empty_charstring)

        outline = extractor.extract(32)

        expect(outline).to be_nil
      end

      it "returns nil when charstring is nil" do
        allow(cff).to receive(:charstring_for_glyph).with(0).and_return(nil)

        outline = extractor.extract(0)

        expect(outline).to be_nil
      end

      it "handles CFF curve commands" do
        curve_charstring = double(
          "Charstring",
          path: [
            { type: :move_to, x: 100.0, y: 0.0 },
            { type: :curve_to, x1: 120.0, y1: 50.0, x2: 180.0, y2: 50.0,
              x: 200.0, y: 0.0 },
          ],
          bounding_box: [100.0, 0.0, 200.0, 50.0],
        )

        allow(cff).to receive(:charstring_for_glyph).with(65).and_return(curve_charstring)

        outline = extractor.extract(65)

        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
        # CFF curves are converted to contour points
        expect(outline.point_count).to be >= 2
      end

      it "raises MissingTableError when CFF table is missing" do
        allow(font).to receive(:table).with(Fontisan::Constants::CFF_TAG).and_return(nil)

        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /CFF/,
        )
      end
    end

    context "with neither glyf nor CFF table" do
      before do
        allow(font).to receive(:has_table?).with("glyf").and_return(false)
        allow(font).to receive(:has_table?).with(Fontisan::Constants::CFF_TAG).and_return(false)
        allow(font).to receive(:table).with("glyf").and_return(nil)
        allow(font).to receive(:table).with(Fontisan::Constants::CFF_TAG).and_return(nil)
      end

      it "raises MissingTableError" do
        expect { extractor.extract(65) }.to raise_error(
          Fontisan::MissingTableError,
          /neither glyf nor CFF/,
        )
      end
    end
  end
end
