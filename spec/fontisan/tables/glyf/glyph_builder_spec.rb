# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::GlyphBuilder do
  describe ".build_simple_glyph" do
    context "with valid outline" do
      it "builds simple glyph from triangle outline" do
        outline = Fontisan::Models::Outline.new(
          glyph_id: 1,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            { type: :line_to, x: 200, y: 700 },
            { type: :line_to, x: 300, y: 0 },
            { type: :close_path },
          ],
          bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
        )

        data = described_class.build_simple_glyph(outline)

        expect(data).to be_a(String)
        expect(data.encoding).to eq(Encoding::BINARY)
        expect(data.bytesize).to be > 10 # At least header size
      end

      it "builds glyph with quadratic curves" do
        outline = Fontisan::Models::Outline.new(
          glyph_id: 2,
          commands: [
            { type: :move_to, x: 0, y: 0 },
            { type: :quad_to, cx: 50, cy: 100, x: 100, y: 0 },
            { type: :close_path },
          ],
          bbox: { x_min: 0, y_min: 0, x_max: 100, y_max: 75 },
        )

        data = described_class.build_simple_glyph(outline)

        expect(data).to be_a(String)
        expect(data.bytesize).to be > 10
      end

      it "builds glyph with multiple contours" do
        outline = Fontisan::Models::Outline.new(
          glyph_id: 3,
          commands: [
            { type: :move_to, x: 0, y: 0 },
            { type: :line_to, x: 100, y: 0 },
            { type: :line_to, x: 100, y: 100 },
            { type: :line_to, x: 0, y: 100 },
            { type: :close_path },
            { type: :move_to, x: 25, y: 25 },
            { type: :line_to, x: 75, y: 25 },
            { type: :line_to, x: 75, y: 75 },
            { type: :line_to, x: 25, y: 75 },
            { type: :close_path },
          ],
          bbox: { x_min: 0, y_min: 0, x_max: 100, y_max: 100 },
        )

        data = described_class.build_simple_glyph(outline)

        expect(data).to be_a(String)
        expect(data.bytesize).to be > 10
      end

      it "includes instructions when provided" do
        outline = Fontisan::Models::Outline.new(
          glyph_id: 4,
          commands: [
            { type: :move_to, x: 0, y: 0 },
            { type: :line_to, x: 100, y: 100 },
            { type: :close_path },
          ],
          bbox: { x_min: 0, y_min: 0, x_max: 100, y_max: 100 },
        )

        instructions = [0xB0, 0x40].pack("C*")
        data = described_class.build_simple_glyph(outline, instructions: instructions)

        expect(data).to be_a(String)
        expect(data).to include(instructions)
      end
    end

    context "with invalid input" do
      it "raises error for nil outline" do
        expect do
          described_class.build_simple_glyph(nil)
        end.to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises error for non-Outline object" do
        expect do
          described_class.build_simple_glyph("not an outline")
        end.to raise_error(ArgumentError, /must be Outline/)
      end

      it "raises error for empty outline" do
        outline = Fontisan::Models::Outline.new(
          glyph_id: 5,
          commands: [],
          bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
        )

        expect do
          described_class.build_simple_glyph(outline)
        end.to raise_error(ArgumentError, /cannot be empty/)
      end
    end
  end

  describe ".build_compound_glyph" do
    context "with valid components" do
      it "builds compound glyph with simple offsets" do
        components = [
          { glyph_index: 10, x_offset: 0, y_offset: 0 },
          { glyph_index: 20, x_offset: 100, y_offset: 0 },
        ]
        bbox = { x_min: 0, y_min: 0, x_max: 500, y_max: 700 }

        data = described_class.build_compound_glyph(components, bbox)

        expect(data).to be_a(String)
        expect(data.encoding).to eq(Encoding::BINARY)
        expect(data.bytesize).to be > 10 # At least header size
      end

      it "builds compound glyph with uniform scale" do
        components = [
          { glyph_index: 15, x_offset: 50, y_offset: 50, scale: 0.5 },
        ]
        bbox = { x_min: 0, y_min: 0, x_max: 200, y_max: 200 }

        data = described_class.build_compound_glyph(components, bbox)

        expect(data).to be_a(String)
        expect(data.bytesize).to be > 10
      end

      it "builds compound glyph with separate x,y scale" do
        components = [
          { glyph_index: 25, x_offset: 0, y_offset: 0, scale_x: 1.5, scale_y: 0.8 },
        ]
        bbox = { x_min: 0, y_min: 0, x_max: 300, y_max: 400 }

        data = described_class.build_compound_glyph(components, bbox)

        expect(data).to be_a(String)
        expect(data.bytesize).to be > 10
      end

      it "builds compound glyph with 2x2 transformation matrix" do
        components = [
          {
            glyph_index: 30,
            x_offset: 100,
            y_offset: 100,
            scale_x: 1.0,
            scale_y: 1.0,
            scale_01: 0.2,
            scale_10: 0.3,
          },
        ]
        bbox = { x_min: 0, y_min: 0, x_max: 500, y_max: 500 }

        data = described_class.build_compound_glyph(components, bbox)

        expect(data).to be_a(String)
        expect(data.bytesize).to be > 10
      end

      it "builds compound glyph with USE_MY_METRICS flag" do
        components = [
          { glyph_index: 40, x_offset: 0, y_offset: 0, use_my_metrics: true },
        ]
        bbox = { x_min: 0, y_min: 0, x_max: 600, y_max: 800 }

        data = described_class.build_compound_glyph(components, bbox)

        expect(data).to be_a(String)
        expect(data.bytesize).to be > 10
      end

      it "builds compound glyph with OVERLAP_COMPOUND flag" do
        components = [
          { glyph_index: 50, x_offset: 0, y_offset: 0, overlap: true },
        ]
        bbox = { x_min: 0, y_min: 0, x_max: 400, y_max: 600 }

        data = described_class.build_compound_glyph(components, bbox)

        expect(data).to be_a(String)
        expect(data.bytesize).to be > 10
      end

      it "builds compound glyph with instructions" do
        components = [
          { glyph_index: 60, x_offset: 0, y_offset: 0 },
        ]
        bbox = { x_min: 0, y_min: 0, x_max: 300, y_max: 400 }
        instructions = [0xB0, 0x80].pack("C*")

        data = described_class.build_compound_glyph(components, bbox, instructions: instructions)

        expect(data).to be_a(String)
        expect(data).to include(instructions)
      end

      it "builds compound glyph with large offsets requiring 16-bit encoding" do
        components = [
          { glyph_index: 70, x_offset: 500, y_offset: -300 },
        ]
        bbox = { x_min: 0, y_min: -300, x_max: 1000, y_max: 700 }

        data = described_class.build_compound_glyph(components, bbox)

        expect(data).to be_a(String)
        expect(data.bytesize).to be > 10
      end

      it "builds compound glyph with small offsets using 8-bit encoding" do
        components = [
          { glyph_index: 80, x_offset: 50, y_offset: -50 },
        ]
        bbox = { x_min: 0, y_min: -50, x_max: 200, y_max: 150 }

        data = described_class.build_compound_glyph(components, bbox)

        expect(data).to be_a(String)
        expect(data.bytesize).to be > 10
      end
    end

    context "with invalid input" do
      it "raises error for nil components" do
        bbox = { x_min: 0, y_min: 0, x_max: 100, y_max: 100 }

        expect do
          described_class.build_compound_glyph(nil, bbox)
        end.to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises error for non-Array components" do
        bbox = { x_min: 0, y_min: 0, x_max: 100, y_max: 100 }

        expect do
          described_class.build_compound_glyph("not array", bbox)
        end.to raise_error(ArgumentError, /must be Array/)
      end

      it "raises error for empty components" do
        bbox = { x_min: 0, y_min: 0, x_max: 100, y_max: 100 }

        expect do
          described_class.build_compound_glyph([], bbox)
        end.to raise_error(ArgumentError, /cannot be empty/)
      end

      it "raises error for invalid bbox" do
        components = [{ glyph_index: 10 }]

        expect do
          described_class.build_compound_glyph(components, nil)
        end.to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises error for bbox missing keys" do
        components = [{ glyph_index: 10 }]
        bbox = { x_min: 0, y_min: 0 }

        expect do
          described_class.build_compound_glyph(components, bbox)
        end.to raise_error(ArgumentError, /missing keys/)
      end

      it "raises error for invalid bbox coordinates" do
        components = [{ glyph_index: 10 }]
        bbox = { x_min: 100, y_min: 0, x_max: 50, y_max: 100 }

        expect do
          described_class.build_compound_glyph(components, bbox)
        end.to raise_error(ArgumentError, /x_min must be <= x_max/)
      end

      it "raises error for component without glyph_index" do
        components = [{ x_offset: 0, y_offset: 0 }]
        bbox = { x_min: 0, y_min: 0, x_max: 100, y_max: 100 }

        expect do
          described_class.build_compound_glyph(components, bbox)
        end.to raise_error(ArgumentError, /must have :glyph_index/)
      end

      it "raises error for negative glyph_index" do
        components = [{ glyph_index: -1 }]
        bbox = { x_min: 0, y_min: 0, x_max: 100, y_max: 100 }

        expect do
          described_class.build_compound_glyph(components, bbox)
        end.to raise_error(ArgumentError, /must be non-negative/)
      end
    end
  end

  describe "coordinate encoding" do
    it "encodes coordinates with delta compression" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 100,
        commands: [
          { type: :move_to, x: 100, y: 100 },
          { type: :line_to, x: 200, y: 100 },
          { type: :line_to, x: 200, y: 200 },
          { type: :line_to, x: 100, y: 200 },
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 100, x_max: 200, y_max: 200 },
      )

      data = described_class.build_simple_glyph(outline)

      expect(data).to be_a(String)
      expect(data.bytesize).to be > 10
    end

    it "handles zero deltas efficiently" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 101,
        commands: [
          { type: :move_to, x: 100, y: 100 },
          { type: :line_to, x: 200, y: 100 }, # y delta = 0
          { type: :line_to, x: 200, y: 200 }, # x delta = 0
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 100, x_max: 200, y_max: 200 },
      )

      data = described_class.build_simple_glyph(outline)

      expect(data).to be_a(String)
      expect(data.bytesize).to be > 10
    end

    it "handles large coordinate deltas" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 102,
        commands: [
          { type: :move_to, x: 0, y: 0 },
          { type: :line_to, x: 1000, y: 1000 },
          { type: :close_path },
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 1000, y_max: 1000 },
      )

      data = described_class.build_simple_glyph(outline)

      expect(data).to be_a(String)
      expect(data.bytesize).to be > 10
    end

    it "handles negative coordinates" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 103,
        commands: [
          { type: :move_to, x: 100, y: 100 },
          { type: :line_to, x: -100, y: -100 },
          { type: :close_path },
        ],
        bbox: { x_min: -100, y_min: -100, x_max: 100, y_max: 100 },
      )

      data = described_class.build_simple_glyph(outline)

      expect(data).to be_a(String)
      expect(data.bytesize).to be > 10
    end
  end

  describe "flag compression" do
    it "compresses repeated flags with RLE" do
      # Create outline with many on-curve points (repeated flags)
      commands = [{ type: :move_to, x: 0, y: 0 }]
      10.times do |i|
        commands << { type: :line_to, x: i * 10, y: 0 }
      end
      commands << { type: :close_path }

      outline = Fontisan::Models::Outline.new(
        glyph_id: 200,
        commands: commands,
        bbox: { x_min: 0, y_min: 0, x_max: 90, y_max: 0 },
      )

      data = described_class.build_simple_glyph(outline)

      expect(data).to be_a(String)
      # With RLE, should be more compact
      expect(data.bytesize).to be < 200
    end

    it "handles mixed on-curve and off-curve flags" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 201,
        commands: [
          { type: :move_to, x: 0, y: 0 },
          { type: :quad_to, cx: 50, cy: 100, x: 100, y: 0 },
          { type: :line_to, x: 150, y: 0 },
          { type: :quad_to, cx: 200, cy: 50, x: 250, y: 0 },
          { type: :close_path },
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 250, y_max: 75 },
      )

      data = described_class.build_simple_glyph(outline)

      expect(data).to be_a(String)
      expect(data.bytesize).to be > 10
    end
  end

  describe "bounding box calculation" do
    it "calculates correct bbox for simple contour" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 300,
        commands: [
          { type: :move_to, x: 50, y: 50 },
          { type: :line_to, x: 150, y: 50 },
          { type: :line_to, x: 150, y: 150 },
          { type: :line_to, x: 50, y: 150 },
          { type: :close_path },
        ],
        bbox: { x_min: 50, y_min: 50, x_max: 150, y_max: 150 },
      )

      data = described_class.build_simple_glyph(outline)

      # Parse header to verify bbox
      header = data[0, 10].unpack("n5")
      num_contours = header[0] > 0x7FFF ? header[0] - 0x10000 : header[0]
      x_min = header[1] > 0x7FFF ? header[1] - 0x10000 : header[1]
      y_min = header[2] > 0x7FFF ? header[2] - 0x10000 : header[2]
      x_max = header[3] > 0x7FFF ? header[3] - 0x10000 : header[3]
      y_max = header[4] > 0x7FFF ? header[4] - 0x10000 : header[4]

      expect(num_contours).to eq(1)
      expect(x_min).to eq(50)
      expect(y_min).to eq(50)
      expect(x_max).to eq(150)
      expect(y_max).to eq(150)
    end

    it "calculates correct bbox with negative coordinates" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 301,
        commands: [
          { type: :move_to, x: -50, y: -50 },
          { type: :line_to, x: 50, y: 50 },
          { type: :close_path },
        ],
        bbox: { x_min: -50, y_min: -50, x_max: 50, y_max: 50 },
      )

      data = described_class.build_simple_glyph(outline)

      # Parse header to verify bbox
      header = data[0, 10].unpack("n5")
      x_min = header[1] > 0x7FFF ? header[1] - 0x10000 : header[1]
      y_min = header[2] > 0x7FFF ? header[2] - 0x10000 : header[2]
      x_max = header[3] > 0x7FFF ? header[3] - 0x10000 : header[3]
      y_max = header[4] > 0x7FFF ? header[4] - 0x10000 : header[4]

      expect(x_min).to eq(-50)
      expect(y_min).to eq(-50)
      expect(x_max).to eq(50)
      expect(y_max).to eq(50)
    end
  end

  describe "round-trip validation" do
    it "can build and parse back simple glyph" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 400,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 150, y: 100 },
          { type: :line_to, x: 200, y: 0 },
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 100 },
      )

      # Build glyph
      data = described_class.build_simple_glyph(outline)

      # Parse it back
      glyph = Fontisan::Tables::SimpleGlyph.parse(data, 400)

      expect(glyph.num_contours).to eq(1)
      expect(glyph.x_min).to eq(100)
      expect(glyph.y_min).to eq(0)
      expect(glyph.x_max).to eq(200)
      expect(glyph.y_max).to eq(100)
      expect(glyph.num_points).to eq(3)
    end

    it "can build and parse back compound glyph" do
      components = [
        { glyph_index: 10, x_offset: 0, y_offset: 0 },
        { glyph_index: 20, x_offset: 100, y_offset: 0 },
      ]
      bbox = { x_min: 0, y_min: 0, x_max: 500, y_max: 700 }

      # Build glyph
      data = described_class.build_compound_glyph(components, bbox)

      # Parse it back
      glyph = Fontisan::Tables::CompoundGlyph.parse(data, 500)

      expect(glyph.compound?).to be true
      expect(glyph.x_min).to eq(0)
      expect(glyph.y_min).to eq(0)
      expect(glyph.x_max).to eq(500)
      expect(glyph.y_max).to eq(700)
      expect(glyph.num_components).to eq(2)
      expect(glyph.component_glyph_ids).to eq([10, 20])
    end

    it "preserves point coordinates in round-trip" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 401,
        commands: [
          { type: :move_to, x: 50, y: 50 },
          { type: :line_to, x: 150, y: 50 },
          { type: :line_to, x: 150, y: 150 },
          { type: :line_to, x: 50, y: 150 },
          { type: :close_path },
        ],
        bbox: { x_min: 50, y_min: 50, x_max: 150, y_max: 150 },
      )

      # Build and parse
      data = described_class.build_simple_glyph(outline)
      glyph = Fontisan::Tables::SimpleGlyph.parse(data, 401)

      # Verify coordinates
      points = glyph.points_for_contour(0)
      expect(points[0][:x]).to eq(50)
      expect(points[0][:y]).to eq(50)
      expect(points[1][:x]).to eq(150)
      expect(points[1][:y]).to eq(50)
      expect(points[2][:x]).to eq(150)
      expect(points[2][:y]).to eq(150)
      expect(points[3][:x]).to eq(50)
      expect(points[3][:y]).to eq(150)
    end
  end

  describe "edge cases" do
    it "handles single-point contour" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 500,
        commands: [
          { type: :move_to, x: 100, y: 100 },
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 100, x_max: 100, y_max: 100 },
      )

      data = described_class.build_simple_glyph(outline)

      expect(data).to be_a(String)
      expect(data.bytesize).to be > 10
    end

    it "handles very large coordinates" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 501,
        commands: [
          { type: :move_to, x: 0, y: 0 },
          { type: :line_to, x: 32000, y: 16000 },
          { type: :close_path },
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 32000, y_max: 16000 },
      )

      data = described_class.build_simple_glyph(outline)

      expect(data).to be_a(String)
      expect(data.bytesize).to be > 10
    end

    it "handles component with zero offset and no transformation" do
      components = [
        { glyph_index: 10 },
      ]
      bbox = { x_min: 0, y_min: 0, x_max: 100, y_max: 100 }

      data = described_class.build_compound_glyph(components, bbox)

      expect(data).to be_a(String)
      expect(data.bytesize).to be > 10
    end

    it "handles F2DOT14 boundary values for scale" do
      components = [
        { glyph_index: 10, scale: 1.99 },
      ]
      bbox = { x_min: 0, y_min: 0, x_max: 200, y_max: 200 }

      data = described_class.build_compound_glyph(components, bbox)

      expect(data).to be_a(String)
      expect(data.bytesize).to be > 10
    end
  end
end
