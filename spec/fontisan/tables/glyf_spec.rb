# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Glyf do
  # Test fixtures acknowledgment:
  # Using Libertinus fonts (OFL licensed) from:
  # https://github.com/alerque/libertinus
  # Copyright © 2012-2023 The Libertinus Project Authors
  #
  # Additional reference implementations:
  # - ttfunk: https://github.com/prawnpdf/ttfunk/blob/master/lib/ttfunk/table/glyf.rb
  # - fonttools: https://github.com/fonttools/fonttools/blob/main/Lib/fontTools/ttLib/tables/_g_l_y_f.py
  # - Allsorts: https://github.com/yeslogic/allsorts/blob/master/src/tables/glyf.rs

  # Helper to build a simple glyph binary structure
  #
  # Based on OpenType specification for glyf table - simple glyph:
  # https://docs.microsoft.com/en-us/typography/opentype/spec/glyf
  #
  # @param num_contours [Integer] Number of contours (>= 0 for simple glyphs)
  # @param bbox [Array<Integer>] Bounding box [xMin, yMin, xMax, yMax]
  # @param end_pts [Array<Integer>] End points for each contour
  # @param flags [Array<Integer>] Point flags
  # @param x_coords [Array<Integer>] X coordinates (absolute)
  # @param y_coords [Array<Integer>] Y coordinates (absolute)
  # @return [String] Binary glyph data
  def build_simple_glyph(num_contours:, bbox:, end_pts:, flags:, x_coords:,
y_coords:)
    data = (+"").b

    # Header: numberOfContours, xMin, yMin, xMax, yMax
    data << [num_contours, bbox[0], bbox[1], bbox[2], bbox[3]].pack("n5")

    # End points of contours
    end_pts.each { |pt| data << [pt].pack("n") }

    # Instruction length (0 for simplicity)
    data << [0].pack("n")

    # Flags (with run-length encoding)
    encoded_flags = encode_flags(flags)
    data << encoded_flags

    # Coordinates (delta-encoded)
    data << encode_coordinates(x_coords, flags, :x)
    data << encode_coordinates(y_coords, flags, :y)

    data
  end

  # Encode flags with run-length compression
  def encode_flags(flags)
    data = (+"").b
    i = 0

    while i < flags.length
      flag = flags[i]
      # Count consecutive identical flags (excluding REPEAT_FLAG bit)
      base_flag = flag & ~0x08
      count = 1
      while i + count < flags.length && (flags[i + count] & ~0x08) == base_flag && count < 256
        count += 1
      end

      if count > 1
        # Use repeat flag
        data << [base_flag | 0x08].pack("C") # Set REPEAT_FLAG bit
        data << [count - 1].pack("C") # Repeat count (n-1 additional times)
      else
        data << [flag].pack("C")
      end

      i += count
    end

    data
  end

  # Encode coordinates with delta encoding
  def encode_coordinates(coords, flags, axis)
    data = (+"").b
    short_flag = axis == :x ? 0x02 : 0x04
    same_or_positive_flag = axis == :x ? 0x10 : 0x20

    prev = 0
    coords.each_with_index do |coord, i|
      delta = coord - prev
      flag = flags[i]

      if flag.anybits?(short_flag)
        # Short coordinate (1 byte)
        value = delta.abs
        data << [value].pack("C")
      elsif flag.anybits?(same_or_positive_flag)
        # Same as previous (delta = 0), no data
      else
        # Long coordinate (2 bytes, signed)
        data << [delta].pack("n") if delta >= 0
        data << [(delta + 0x10000) & 0xFFFF].pack("n") if delta < 0
      end

      prev = coord
    end

    data
  end

  # Helper to build a compound glyph binary structure
  #
  # @param bbox [Array<Integer>] Bounding box [xMin, yMin, xMax, yMax]
  # @param components [Array<Hash>] Component descriptions
  # @return [String] Binary glyph data
  def build_compound_glyph(bbox:, components:)
    data = (+"").b

    # Header: numberOfContours (-1), xMin, yMin, xMax, yMax
    data << [0xFFFF, bbox[0], bbox[1], bbox[2], bbox[3]].pack("n5")

    # Components
    components.each_with_index do |comp, i|
      flags = comp[:flags]
      flags |= 0x0020 if i < components.length - 1 # MORE_COMPONENTS

      data << [flags].pack("n")
      data << [comp[:glyph_index]].pack("n")

      # Arguments
      data << if flags.nobits?(0x0001)
                # 8-bit args
                [comp[:arg1], comp[:arg2]].pack("C2")
              else
                # 16-bit args
                [comp[:arg1], comp[:arg2]].pack("n2")
              end

      # Transformation
      if flags.anybits?(0x0080)
        # 2x2 matrix
        scale_values = [comp[:scale_x], comp[:scale_01], comp[:scale_10],
                        comp[:scale_y]]
        scale_values.each { |v| data << [(v * 16384).to_i].pack("n") }
      elsif flags.anybits?(0x0040)
        # X and Y scale
        data << [(comp[:scale_x] * 16384).to_i].pack("n")
        data << [(comp[:scale_y] * 16384).to_i].pack("n")
      elsif flags.anybits?(0x0008)
        # Uniform scale
        data << [(comp[:scale_x] * 16384).to_i].pack("n")
      end
    end

    data
  end

  # Helper to create mock Head table
  def mock_head_table
    double("Head", units_per_em: 2048, index_to_loc_format: 1)
  end

  # Helper to create mock Loca table
  def mock_loca_table(offsets)
    loca = double("Loca")
    allow(loca).to receive(:offset_for) { |id| offsets[id] }
    allow(loca).to receive(:size_of) do |id|
      next nil if id >= offsets.length - 1

      offsets[id + 1] - offsets[id]
    end
    allow(loca).to receive_messages(parsed?: true,
                                    num_glyphs: offsets.length - 1)
    allow(loca).to receive(:respond_to?).with(:offset_for).and_return(true)
    allow(loca).to receive(:respond_to?).with(:size_of).and_return(true)
    loca
  end

  describe ".read" do
    it "reads glyf table data" do
      data = "test glyph data"
      glyf = described_class.read(data)

      expect(glyf).to be_a(described_class)
      expect(glyf.raw_data).to eq(data)
    end

    it "handles nil data gracefully" do
      expect { described_class.read(nil) }.not_to raise_error
    end

    it "handles empty string gracefully" do
      expect { described_class.read("") }.not_to raise_error
    end

    it "initializes with empty cache" do
      glyf = described_class.read("data")
      expect(glyf.cache_size).to eq(0)
    end
  end

  describe "#glyph_for" do
    let(:simple_glyph_data) do
      build_simple_glyph(
        num_contours: 1,
        bbox: [10, 20, 100, 200],
        end_pts: [3],
        flags: [0x01, 0x01, 0x01, 0x01], # All on-curve
        x_coords: [10, 50, 90, 10],
        y_coords: [20, 180, 20, 20],
      )
    end

    let(:compound_glyph_data) do
      build_compound_glyph(
        bbox: [0, 0, 100, 200],
        components: [
          { flags: 0x0003, glyph_index: 10, arg1: 0, arg2: 0, scale_x: 1.0,
            scale_y: 1.0 },
          { flags: 0x0003, glyph_index: 20, arg1: 50, arg2: 0, scale_x: 1.0,
            scale_y: 1.0 },
        ],
      )
    end

    let(:glyf_data) { simple_glyph_data + compound_glyph_data }
    let(:glyf) { described_class.read(glyf_data) }
    let(:head) { mock_head_table }
    let(:loca) do
      mock_loca_table([0, simple_glyph_data.length, glyf_data.length])
    end

    context "with simple glyph" do
      it "returns a SimpleGlyph instance" do
        glyph = glyf.glyph_for(0, loca, head)

        expect(glyph).to be_a(Fontisan::Tables::SimpleGlyph)
        expect(glyph).to be_simple
        expect(glyph).not_to be_compound
      end

      it "parses header correctly" do
        glyph = glyf.glyph_for(0, loca, head)

        expect(glyph.num_contours).to eq(1)
        expect(glyph.bounding_box).to eq([10, 20, 100, 200])
      end

      it "caches parsed glyphs" do
        glyph1 = glyf.glyph_for(0, loca, head)
        glyph2 = glyf.glyph_for(0, loca, head)

        expect(glyph1).to be(glyph2) # Same object reference
        expect(glyf).to be_cached(0)
        expect(glyf.cache_size).to eq(1)
      end
    end

    context "with compound glyph" do
      it "returns a CompoundGlyph instance" do
        glyph = glyf.glyph_for(1, loca, head)

        expect(glyph).to be_a(Fontisan::Tables::CompoundGlyph)
        expect(glyph).to be_compound
        expect(glyph).not_to be_simple
      end

      it "parses header correctly" do
        glyph = glyf.glyph_for(1, loca, head)

        expect(glyph.bounding_box).to eq([0, 0, 100, 200])
      end

      it "parses components correctly" do
        glyph = glyf.glyph_for(1, loca, head)

        expect(glyph.num_components).to eq(2)
        expect(glyph.component_glyph_ids).to eq([10, 20])
      end
    end

    context "with empty glyph" do
      let(:empty_loca) { mock_loca_table([0, 0, 100]) }

      it "returns nil for empty glyph" do
        glyph = glyf.glyph_for(0, empty_loca, head)
        expect(glyph).to be_nil
      end

      it "caches nil result" do
        glyf.glyph_for(0, empty_loca, head)
        expect(glyf).to be_cached(0)
      end
    end

    context "with validation" do
      it "validates loca table" do
        invalid_loca = double("Invalid")

        expect do
          glyf.glyph_for(0, invalid_loca, head)
        end.to raise_error(ArgumentError, /loca must be a parsed Loca table/)
      end

      it "requires parsed loca table" do
        unparsed_loca = mock_loca_table([0, 100])
        allow(unparsed_loca).to receive(:parsed?).and_return(false)

        expect do
          glyf.glyph_for(0, unparsed_loca, head)
        end.to raise_error(ArgumentError, /loca table must be parsed/)
      end

      it "validates head table" do
        invalid_head = double("Invalid")

        expect do
          glyf.glyph_for(0, loca, invalid_head)
        end.to raise_error(ArgumentError, /head must be a parsed Head table/)
      end

      it "validates glyph_id range" do
        expect do
          glyf.glyph_for(-1, loca, head)
        end.to raise_error(ArgumentError, /glyph_id must be >= 0/)
      end

      it "validates glyph_id does not exceed num_glyphs" do
        expect do
          glyf.glyph_for(10, loca, head)
        end.to raise_error(ArgumentError, /exceeds number of glyphs/)
      end

      it "raises error if glyph extends beyond table" do
        bad_loca = mock_loca_table([0, 10000])

        expect do
          glyf.glyph_for(0, bad_loca, head)
        end.to raise_error(Fontisan::CorruptedTableError,
                           /extends beyond glyf table/)
      end
    end
  end

  describe "#clear_cache" do
    let(:simple_glyph_data) do
      build_simple_glyph(
        num_contours: 1,
        bbox: [0, 0, 100, 100],
        end_pts: [3],
        flags: [0x01, 0x01, 0x01, 0x01],
        x_coords: [0, 100, 100, 0],
        y_coords: [0, 0, 100, 100],
      )
    end

    let(:glyf) { described_class.read(simple_glyph_data) }
    let(:head) { mock_head_table }
    let(:loca) { mock_loca_table([0, simple_glyph_data.length]) }

    it "clears cached glyphs" do
      glyf.glyph_for(0, loca, head)
      expect(glyf.cache_size).to eq(1)

      glyf.clear_cache
      expect(glyf.cache_size).to eq(0)
      expect(glyf).not_to be_cached(0)
    end
  end

  describe Fontisan::Tables::SimpleGlyph do
    let(:glyph_data) do
      build_simple_glyph(
        num_contours: 2,
        bbox: [10, 20, 200, 300],
        end_pts: [3, 7],
        flags: [0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01],
        x_coords: [10, 50, 90, 10, 120, 160, 180, 120],
        y_coords: [20, 280, 20, 20, 50, 250, 50, 50],
      )
    end

    let(:glyph) { described_class.parse(glyph_data, 42) }

    describe ".parse" do
      it "parses simple glyph successfully" do
        expect(glyph).to be_a(described_class)
        expect(glyph.glyph_id).to eq(42)
      end

      it "parses header correctly" do
        expect(glyph.num_contours).to eq(2)
        expect(glyph.x_min).to eq(10)
        expect(glyph.y_min).to eq(20)
        expect(glyph.x_max).to eq(200)
        expect(glyph.y_max).to eq(300)
      end

      it "parses contour end points" do
        expect(glyph.end_pts_of_contours).to eq([3, 7])
      end

      it "parses flags" do
        expect(glyph.flags.length).to eq(8)
        # Flags might have REPEAT_FLAG bit set during encoding, so check base flag
        expect(glyph.flags.all? { |f| f.allbits?(0x01) }).to be true
      end

      it "parses coordinates" do
        expect(glyph.x_coordinates.length).to eq(8)
        expect(glyph.y_coordinates.length).to eq(8)
        expect(glyph.x_coordinates.first).to eq(10)
        expect(glyph.y_coordinates.first).to eq(20)
      end
    end

    describe "#simple?" do
      it "returns true" do
        expect(glyph).to be_simple
      end
    end

    describe "#compound?" do
      it "returns false" do
        expect(glyph).not_to be_compound
      end
    end

    describe "#empty?" do
      it "returns false for non-empty glyph" do
        expect(glyph).not_to be_empty
      end

      it "returns true for empty glyph" do
        empty_data = build_simple_glyph(
          num_contours: 0,
          bbox: [0, 0, 0, 0],
          end_pts: [],
          flags: [],
          x_coords: [],
          y_coords: [],
        )
        empty_glyph = described_class.parse(empty_data, 0)
        expect(empty_glyph).to be_empty
      end
    end

    describe "#bounding_box" do
      it "returns bounding box as array" do
        expect(glyph.bounding_box).to eq([10, 20, 200, 300])
      end
    end

    describe "#num_points" do
      it "returns total point count" do
        expect(glyph.num_points).to eq(8)
      end
    end

    describe "#on_curve?" do
      it "returns true for on-curve points" do
        expect(glyph.on_curve?(0)).to be true
        expect(glyph.on_curve?(7)).to be true
      end

      it "returns nil for invalid index" do
        expect(glyph.on_curve?(-1)).to be_nil
        expect(glyph.on_curve?(100)).to be_nil
      end
    end

    describe "#contour_for_point" do
      it "returns correct contour index" do
        expect(glyph.contour_for_point(0)).to eq(0)
        expect(glyph.contour_for_point(3)).to eq(0)
        expect(glyph.contour_for_point(4)).to eq(1)
        expect(glyph.contour_for_point(7)).to eq(1)
      end

      it "returns nil for invalid point" do
        expect(glyph.contour_for_point(-1)).to be_nil
        expect(glyph.contour_for_point(100)).to be_nil
      end
    end

    describe "#points_for_contour" do
      it "returns points for first contour" do
        points = glyph.points_for_contour(0)
        expect(points.length).to eq(4)
        expect(points.first[:x]).to eq(10)
        expect(points.first[:y]).to eq(20)
        expect(points.first[:on_curve]).to be true
      end

      it "returns points for second contour" do
        points = glyph.points_for_contour(1)
        expect(points.length).to eq(4)
        expect(points.first[:x]).to eq(120)
      end

      it "returns nil for invalid contour" do
        expect(glyph.points_for_contour(-1)).to be_nil
        expect(glyph.points_for_contour(10)).to be_nil
      end
    end
  end

  describe Fontisan::Tables::CompoundGlyph do
    let(:glyph_data) do
      build_compound_glyph(
        bbox: [0, 0, 200, 300],
        components: [
          {
            flags: 0x0003,
            glyph_index: 10,
            arg1: 0,
            arg2: 0,
            scale_x: 1.0,
            scale_y: 1.0,
          },
          {
            flags: 0x0003,
            glyph_index: 20,
            arg1: 100,
            arg2: 50,
            scale_x: 1.0,
            scale_y: 1.0,
          },
        ],
      )
    end

    let(:glyph) { described_class.parse(glyph_data, 100) }

    describe ".parse" do
      it "parses compound glyph successfully" do
        expect(glyph).to be_a(described_class)
        expect(glyph.glyph_id).to eq(100)
      end

      it "parses header correctly" do
        expect(glyph.x_min).to eq(0)
        expect(glyph.y_min).to eq(0)
        expect(glyph.x_max).to eq(200)
        expect(glyph.y_max).to eq(300)
      end

      it "parses components" do
        expect(glyph.num_components).to eq(2)
        expect(glyph.components.length).to eq(2)
      end

      it "parses component glyph indices" do
        expect(glyph.components[0].glyph_index).to eq(10)
        expect(glyph.components[1].glyph_index).to eq(20)
      end

      it "parses component arguments" do
        expect(glyph.components[0].arg1).to eq(0)
        expect(glyph.components[0].arg2).to eq(0)
        expect(glyph.components[1].arg1).to eq(100)
        expect(glyph.components[1].arg2).to eq(50)
      end
    end

    describe "#simple?" do
      it "returns false" do
        expect(glyph).not_to be_simple
      end
    end

    describe "#compound?" do
      it "returns true" do
        expect(glyph).to be_compound
      end
    end

    describe "#empty?" do
      it "returns false for non-empty glyph" do
        expect(glyph).not_to be_empty
      end
    end

    describe "#bounding_box" do
      it "returns bounding box as array" do
        expect(glyph.bounding_box).to eq([0, 0, 200, 300])
      end
    end

    describe "#component_glyph_ids" do
      it "returns array of component IDs" do
        expect(glyph.component_glyph_ids).to eq([10, 20])
      end

      it "is useful for subsetting dependency tracking" do
        # When subsetting, all component glyphs must be included
        required_glyphs = [glyph.glyph_id] + glyph.component_glyph_ids
        expect(required_glyphs).to eq([100, 10, 20])
      end
    end

    describe "#uses_component?" do
      it "returns true for used components" do
        expect(glyph.uses_component?(10)).to be true
        expect(glyph.uses_component?(20)).to be true
      end

      it "returns false for unused components" do
        expect(glyph.uses_component?(30)).to be false
      end
    end

    describe "#num_components" do
      it "returns component count" do
        expect(glyph.num_components).to eq(2)
      end
    end

    describe "component transformations" do
      context "with scaling" do
        let(:scaled_data) do
          build_compound_glyph(
            bbox: [0, 0, 100, 100],
            components: [
              {
                flags: 0x000B, # WE_HAVE_A_SCALE (0x0008) | ARGS_ARE_XY_VALUES (0x0002) | ARG_1_AND_2_ARE_WORDS (0x0001)
                glyph_index: 5,
                arg1: 0,
                arg2: 0,
                scale_x: 1.5,  # Use 1.5 instead of 2.0 (F2DOT14 max is ~1.999)
                scale_y: 1.5,
              },
            ],
          )
        end

        let(:scaled_glyph) { described_class.parse(scaled_data, 50) }

        it "parses uniform scale" do
          comp = scaled_glyph.components[0]
          expect(comp.scale_x).to be_within(0.01).of(1.5)
          expect(comp.has_scale?).to be true
        end

        it "provides transformation matrix" do
          comp = scaled_glyph.components[0]
          matrix = comp.transformation_matrix
          expect(matrix[0]).to be_within(0.01).of(1.5) # a (x scale)
          expect(matrix[3]).to be_within(0.01).of(1.5) # d (y scale)
        end
      end
    end

    describe "validation" do
      it "raises error for circular reference" do
        # Glyph referencing itself
        bad_data = build_compound_glyph(
          bbox: [0, 0, 100, 100],
          components: [
            { flags: 0x0003, glyph_index: 100, arg1: 0, arg2: 0, scale_x: 1.0,
              scale_y: 1.0 },
          ],
        )

        expect do
          described_class.parse(bad_data, 100)
        end.to raise_error(Fontisan::CorruptedTableError, /Circular reference/)
      end
    end
  end

  describe "integration with real fonts" do
    let(:libertinus_serif_ttf_path) do
      font_fixture_path("Libertinus",
                        "static/TTF/LibertinusSerif-Regular.ttf")
    end

    context "when reading from TrueType font" do
      it "successfully parses glyf table from Libertinus Serif TTF" do
        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_ttf_path)
        head = font.table("head")
        maxp = font.table("maxp")

        # These tables are required and should exist
        expect(head).not_to be_nil, "head table should exist"
        expect(maxp).not_to be_nil, "maxp table should exist"

        # Parse loca table
        loca_data = font.table_data["loca"]
        expect(loca_data).not_to be_nil, "loca table should exist"

        loca = Fontisan::Tables::Loca.read(loca_data)
        loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)

        # Parse glyf table
        glyf_data = font.table_data["glyf"]
        expect(glyf_data).not_to be_nil, "glyf table should exist"

        glyf = described_class.read(glyf_data)

        # Test .notdef glyph (glyph ID 0)
        notdef = glyf.glyph_for(0, loca, head)
        expect(notdef).not_to be_nil

        # Test a few glyphs
        glyphs_to_test = [0, 1, 2, 10, 20]
        glyphs_to_test.each do |gid|
          next if gid >= maxp.num_glyphs

          glyph = glyf.glyph_for(gid, loca, head)
          next if glyph.nil? # Empty glyph

          # Verify glyph type
          expect(glyph.simple? || glyph.compound?).to be true

          # Verify bounding box
          bbox = glyph.bounding_box
          expect(bbox.length).to eq(4)
          expect(bbox[2]).to be >= bbox[0] # xMax >= xMin
          expect(bbox[3]).to be >= bbox[1] # yMax >= yMin

          # For compound glyphs, verify component dependencies
          if glyph.compound?
            glyph.component_glyph_ids.each do |comp_id|
              expect(comp_id).to be >= 0
              expect(comp_id).to be < maxp.num_glyphs
            end
          end
        end

        # Test caching
        glyf.clear_cache
        expect(glyf.cache_size).to eq(0)

        # Access same glyph twice
        glyph1 = glyf.glyph_for(0, loca, head)
        glyph2 = glyf.glyph_for(0, loca, head)
        expect(glyph1).to be(glyph2) # Same object
        expect(glyf.cache_size).to eq(1)
      end
    end
  end
end
