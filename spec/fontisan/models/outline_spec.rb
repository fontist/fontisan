# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/outline"

RSpec.describe Fontisan::Models::Outline do
  describe ".new" do
    let(:valid_params) do
      {
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 200, y: 700 },
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
      }
    end

    it "creates outline with valid parameters" do
      outline = described_class.new(**valid_params)

      expect(outline.glyph_id).to eq(65)
      expect(outline.commands.length).to eq(3)
      expect(outline.bbox[:x_min]).to eq(100)
    end

    it "accepts optional width parameter" do
      params = valid_params.merge(width: 500)
      outline = described_class.new(**params)

      expect(outline.width).to eq(500)
    end

    it "freezes commands array" do
      outline = described_class.new(**valid_params)

      expect(outline.commands).to be_frozen
    end

    it "freezes bbox hash" do
      outline = described_class.new(**valid_params)

      expect(outline.bbox).to be_frozen
    end

    context "with invalid glyph_id" do
      it "raises error for nil glyph_id" do
        params = valid_params.merge(glyph_id: nil)

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /glyph_id must be non-negative Integer/,
        )
      end

      it "raises error for negative glyph_id" do
        params = valid_params.merge(glyph_id: -1)

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /glyph_id must be non-negative Integer/,
        )
      end

      it "raises error for non-integer glyph_id" do
        params = valid_params.merge(glyph_id: "65")

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /glyph_id must be non-negative Integer/,
        )
      end
    end

    context "with invalid commands" do
      it "raises error for non-array commands" do
        params = valid_params.merge(commands: "not an array")

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /commands must be Array/,
        )
      end

      it "raises error for command without type" do
        params = valid_params.merge(commands: [{ x: 100, y: 0 }])

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /must be Hash with :type key/,
        )
      end

      it "raises error for invalid command type" do
        params = valid_params.merge(
          commands: [{ type: :invalid, x: 100, y: 0 }],
        )

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /has invalid type/,
        )
      end

      it "raises error for move_to missing coordinates" do
        params = valid_params.merge(
          commands: [{ type: :move_to, x: 100 }],
        )

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /missing :x or :y/,
        )
      end

      it "raises error for quad_to missing control point" do
        params = valid_params.merge(
          commands: [{ type: :quad_to, x: 100, y: 0 }],
        )

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /missing required keys/,
        )
      end

      it "raises error for curve_to missing control points" do
        params = valid_params.merge(
          commands: [{ type: :curve_to, x: 100, y: 0 }],
        )

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /missing keys/,
        )
      end
    end

    context "with invalid bbox" do
      it "raises error for non-hash bbox" do
        params = valid_params.merge(bbox: [100, 0, 200, 700])

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /bbox must be Hash/,
        )
      end

      it "raises error for missing bbox keys" do
        params = valid_params.merge(bbox: { x_min: 100, y_min: 0 })

        expect { described_class.new(**params) }.to raise_error(
          ArgumentError,
          /bbox missing keys/,
        )
      end
    end
  end

  describe ".from_truetype" do
    let(:simple_glyph) do
      double(
        "SimpleGlyph",
        simple?: true,
        compound?: false,
        num_contours: 1,
        x_min: 100,
        y_min: 0,
        x_max: 300,
        y_max: 700,
      )
    end

    let(:contour_points) do
      [
        { x: 100, y: 0, on_curve: true },
        { x: 200, y: 700, on_curve: true },
        { x: 300, y: 0, on_curve: true },
      ]
    end

    before do
      allow(simple_glyph).to receive(:points_for_contour)
        .with(0)
        .and_return(contour_points)
    end

    it "creates outline from TrueType glyph" do
      outline = described_class.from_truetype(simple_glyph, 65)

      expect(outline.glyph_id).to eq(65)
      expect(outline.commands).not_to be_empty
      expect(outline.bbox[:x_min]).to eq(100)
      expect(outline.bbox[:x_max]).to eq(300)
    end

    it "converts on-curve points to line_to commands" do
      outline = described_class.from_truetype(simple_glyph, 65)

      expect(outline.commands).to include(
        a_hash_including(type: :move_to, x: 100, y: 0),
      )
      expect(outline.commands).to include(
        a_hash_including(type: :line_to, x: 200, y: 700),
      )
    end

    it "adds close_path command at end" do
      outline = described_class.from_truetype(simple_glyph, 65)

      expect(outline.commands.last).to eq({ type: :close_path })
    end

    it "raises error for nil glyph" do
      expect do
        described_class.from_truetype(nil, 65)
      end.to raise_error(ArgumentError, /glyph cannot be nil/)
    end

    it "raises error for compound glyph" do
      compound = double("CompoundGlyph", simple?: false, compound?: true)

      expect do
        described_class.from_truetype(compound, 65)
      end.to raise_error(ArgumentError, /must be simple glyph/)
    end

    context "with quadratic curves" do
      let(:curve_points) do
        [
          { x: 100, y: 0, on_curve: true },
          { x: 150, y: 350, on_curve: false }, # Control point
          { x: 200, y: 700, on_curve: true },
        ]
      end

      before do
        allow(simple_glyph).to receive(:points_for_contour)
          .with(0)
          .and_return(curve_points)
      end

      it "converts to quad_to commands" do
        outline = described_class.from_truetype(simple_glyph, 65)

        quad_cmd = outline.commands.find { |c| c[:type] == :quad_to }
        expect(quad_cmd).not_to be_nil
        expect(quad_cmd[:cx]).to eq(150)
        expect(quad_cmd[:cy]).to eq(350)
        expect(quad_cmd[:x]).to eq(200)
        expect(quad_cmd[:y]).to eq(700)
      end
    end

    context "with consecutive off-curve points" do
      let(:consecutive_curve_points) do
        [
          { x: 100, y: 0, on_curve: true },
          { x: 120, y: 200, on_curve: false },
          { x: 180, y: 500, on_curve: false },
          { x: 200, y: 700, on_curve: true },
        ]
      end

      before do
        allow(simple_glyph).to receive(:points_for_contour)
          .with(0)
          .and_return(consecutive_curve_points)
      end

      it "creates implied on-curve point at midpoint" do
        outline = described_class.from_truetype(simple_glyph, 65)

        # Should have two quad_to commands
        quad_commands = outline.commands.select { |c| c[:type] == :quad_to }
        expect(quad_commands.length).to eq(2)

        # First curve to implied midpoint
        first_quad = quad_commands[0]
        expect(first_quad[:cx]).to eq(120)
        expect(first_quad[:cy]).to eq(200)
        expect(first_quad[:x]).to eq(150) # Midpoint of 120,180
        expect(first_quad[:y]).to eq(350) # Midpoint of 200,500
      end
    end
  end

  describe ".from_cff" do
    let(:charstring) do
      double("CharString")
    end

    let(:cff_path) do
      [
        { type: :move_to, x: 100.0, y: 0.0 },
        { type: :line_to, x: 200.0, y: 700.0 },
        { type: :curve_to, x1: 250.0, y1: 650.0, x2: 280.0, y2: 550.0,
          x: 300.0, y: 0.0 },
      ]
    end

    let(:bbox_array) { [100, 0, 300, 700] }

    before do
      allow(charstring).to receive_messages(path: cff_path,
                                            bounding_box: bbox_array)
    end

    it "creates outline from CFF CharString" do
      outline = described_class.from_cff(charstring, 65)

      expect(outline.glyph_id).to eq(65)
      expect(outline.commands).not_to be_empty
      expect(outline.bbox[:x_min]).to eq(100)
      expect(outline.bbox[:x_max]).to eq(300)
    end

    it "converts CFF move_to commands" do
      outline = described_class.from_cff(charstring, 65)

      expect(outline.commands).to include(
        a_hash_including(type: :move_to, x: 100, y: 0),
      )
    end

    it "converts CFF line_to commands" do
      outline = described_class.from_cff(charstring, 65)

      expect(outline.commands).to include(
        a_hash_including(type: :line_to, x: 200, y: 700),
      )
    end

    it "converts CFF curve_to commands" do
      outline = described_class.from_cff(charstring, 65)

      curve_cmd = outline.commands.find { |c| c[:type] == :curve_to }
      expect(curve_cmd).not_to be_nil
      expect(curve_cmd[:cx1]).to eq(250)
      expect(curve_cmd[:cy1]).to eq(650)
      expect(curve_cmd[:cx2]).to eq(280)
      expect(curve_cmd[:cy2]).to eq(550)
      expect(curve_cmd[:x]).to eq(300)
      expect(curve_cmd[:y]).to eq(0)
    end

    it "raises error for nil charstring" do
      expect do
        described_class.from_cff(nil, 65)
      end.to raise_error(ArgumentError, /charstring cannot be nil/)
    end

    it "raises error for empty path" do
      allow(charstring).to receive(:path).and_return([])

      expect do
        described_class.from_cff(charstring, 65)
      end.to raise_error(ArgumentError, /has no path data/)
    end

    it "raises error for missing bounding box" do
      allow(charstring).to receive(:bounding_box).and_return(nil)

      expect do
        described_class.from_cff(charstring, 65)
      end.to raise_error(ArgumentError, /has no bounding box/)
    end
  end

  describe "#to_truetype_contours" do
    let(:outline) do
      described_class.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 200, y: 700 },
          { type: :line_to, x: 300, y: 0 },
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )
    end

    it "converts to TrueType contour format" do
      contours = outline.to_truetype_contours

      expect(contours.length).to eq(1)
      expect(contours[0].length).to eq(3)
    end

    it "marks on-curve points correctly" do
      contours = outline.to_truetype_contours

      contours[0].each do |point|
        expect(point[:on_curve]).to be true
      end
    end

    context "with quadratic curves" do
      let(:outline_with_curve) do
        described_class.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            { type: :quad_to, cx: 150, cy: 350, x: 200, y: 700 },
            { type: :close_path },
          ],
          bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
        )
      end

      it "includes control point as off-curve" do
        contours = outline_with_curve.to_truetype_contours

        expect(contours[0].length).to eq(3)
        expect(contours[0][1][:on_curve]).to be false
        expect(contours[0][1][:x]).to eq(150)
        expect(contours[0][1][:y]).to eq(350)
      end
    end

    context "with cubic curves" do
      let(:outline_with_cubic) do
        described_class.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            { type: :curve_to, cx1: 120, cy1: 200, cx2: 180, cy2: 500, x: 200,
              y: 700 },
            { type: :close_path },
          ],
          bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
        )
      end

      it "approximates cubic as quadratic" do
        contours = outline_with_cubic.to_truetype_contours

        # Should convert to quadratic with midpoint control
        expect(contours[0].length).to eq(3)
        expect(contours[0][1][:on_curve]).to be false

        # Control point should be midpoint of cubic controls
        expect(contours[0][1][:x]).to eq(150) # (120 + 180) / 2
        expect(contours[0][1][:y]).to eq(350) # (200 + 500) / 2
      end
    end
  end

  describe "#to_cff_commands" do
    let(:outline) do
      described_class.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 200, y: 700 },
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
      )
    end

    it "converts to CFF command format" do
      cff_commands = outline.to_cff_commands

      expect(cff_commands.length).to eq(2) # move_to and line_to, no close
      expect(cff_commands[0]).to include(type: :move_to, x: 100, y: 0)
      expect(cff_commands[1]).to include(type: :line_to, x: 200, y: 700)
    end

    it "omits close_path commands" do
      cff_commands = outline.to_cff_commands

      expect(cff_commands).not_to include(a_hash_including(type: :close_path))
    end

    context "with quadratic curves" do
      let(:outline_with_quad) do
        described_class.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            { type: :quad_to, cx: 150, cy: 350, x: 200, y: 700 },
            { type: :close_path },
          ],
          bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
        )
      end

      it "elevates quadratic to cubic" do
        cff_commands = outline_with_quad.to_cff_commands

        curve_cmd = cff_commands.find { |c| c[:type] == :curve_to }
        expect(curve_cmd).not_to be_nil

        # Verify cubic control points calculated correctly
        # CP1 = P0 + 2/3*(P1 - P0)
        expect(curve_cmd[:x1]).to be_within(1).of(133) # 100 + 2/3*(150-100)
        expect(curve_cmd[:y1]).to be_within(1).of(233) # 0 + 2/3*(350-0)

        # CP2 = P2 + 2/3*(P1 - P2)
        expect(curve_cmd[:x2]).to be_within(1).of(167) # 200 + 2/3*(150-200)
        expect(curve_cmd[:y2]).to be_within(1).of(467) # 700 + 2/3*(350-700)
      end
    end

    context "with cubic curves" do
      let(:outline_with_cubic) do
        described_class.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            { type: :curve_to, cx1: 120, cy1: 200, cx2: 180, cy2: 500, x: 200,
              y: 700 },
            { type: :close_path },
          ],
          bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
        )
      end

      it "preserves cubic curves directly" do
        cff_commands = outline_with_cubic.to_cff_commands

        curve_cmd = cff_commands.find { |c| c[:type] == :curve_to }
        expect(curve_cmd).not_to be_nil
        expect(curve_cmd[:x1]).to eq(120)
        expect(curve_cmd[:y1]).to eq(200)
        expect(curve_cmd[:x2]).to eq(180)
        expect(curve_cmd[:y2]).to eq(500)
      end
    end
  end

  describe "#empty?" do
    it "returns true for empty commands" do
      outline = described_class.new(
        glyph_id: 0,
        commands: [],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      expect(outline.empty?).to be true
    end

    it "returns true for only close_path commands" do
      outline = described_class.new(
        glyph_id: 0,
        commands: [{ type: :close_path }],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      expect(outline.empty?).to be true
    end

    it "returns false for commands with drawing" do
      outline = described_class.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 200, y: 700 },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
      )

      expect(outline.empty?).to be false
    end
  end

  describe "#command_count" do
    it "returns number of commands" do
      outline = described_class.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 200, y: 700 },
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
      )

      expect(outline.command_count).to eq(3)
    end
  end

  describe "#contour_count" do
    it "counts number of move_to commands" do
      outline = described_class.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 200, y: 700 },
          { type: :close_path },
          { type: :move_to, x: 150, y: 300 },
          { type: :line_to, x: 180, y: 400 },
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
      )

      expect(outline.contour_count).to eq(2)
    end
  end

  describe "#to_s" do
    it "returns human-readable representation" do
      outline = described_class.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 200, y: 700 },
          { type: :close_path },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
      )

      str = outline.to_s

      expect(str).to include("Outline")
      expect(str).to include("glyph_id=65")
      expect(str).to include("commands=3")
      expect(str).to include("contours=1")
    end
  end
end
