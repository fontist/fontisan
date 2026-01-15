# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Models::GlyphOutline do
  describe "#initialize" do
    let(:valid_params) do
      {
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 200, y: 700, on_curve: true },
            { x: 300, y: 0, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      }
    end

    it "creates an outline with valid parameters" do
      outline = described_class.new(**valid_params)

      expect(outline.glyph_id).to eq(65)
      expect(outline.contours.length).to eq(1)
      expect(outline.contours[0].length).to eq(3)
      expect(outline.points.length).to eq(3)
      expect(outline.bbox[:x_min]).to eq(100)
    end

    it "freezes the outline data for immutability" do
      outline = described_class.new(**valid_params)

      expect(outline.glyph_id).to be_frozen
      expect(outline.contours).to be_frozen
      expect(outline.contours[0]).to be_frozen
      expect(outline.points).to be_frozen
      expect(outline.bbox).to be_frozen
    end

    context "with invalid parameters" do
      it "raises ArgumentError for nil glyph_id" do
        params = valid_params.merge(glyph_id: nil)
        expect do
          described_class.new(**params)
        end.to raise_error(ArgumentError, /glyph_id/)
      end

      it "raises ArgumentError for negative glyph_id" do
        params = valid_params.merge(glyph_id: -1)
        expect do
          described_class.new(**params)
        end.to raise_error(ArgumentError, /glyph_id/)
      end

      it "raises ArgumentError for non-Integer glyph_id" do
        params = valid_params.merge(glyph_id: "65")
        expect do
          described_class.new(**params)
        end.to raise_error(ArgumentError, /glyph_id/)
      end

      it "raises ArgumentError for non-Array contours" do
        params = valid_params.merge(contours: "not an array")
        expect do
          described_class.new(**params)
        end.to raise_error(ArgumentError, /contours/)
      end

      it "raises ArgumentError for non-Hash bbox" do
        params = valid_params.merge(bbox: [100, 0, 300, 700])
        expect do
          described_class.new(**params)
        end.to raise_error(ArgumentError, /bbox/)
      end

      it "raises ArgumentError for bbox missing required keys" do
        params = valid_params.merge(bbox: { x_min: 100, y_min: 0 })
        expect do
          described_class.new(**params)
        end.to raise_error(ArgumentError, /bbox missing/)
      end

      it "raises ArgumentError for invalid contour structure" do
        params = valid_params.merge(contours: [["not a hash"]])
        expect do
          described_class.new(**params)
        end.to raise_error(ArgumentError, /must be a Hash/)
      end

      it "raises ArgumentError for point missing required keys" do
        params = valid_params.merge(
          contours: [[{ x: 100, y: 0 }]], # missing on_curve
        )
        expect do
          described_class.new(**params)
        end.to raise_error(ArgumentError, /missing keys/)
      end
    end
  end

  describe "#empty?" do
    it "returns true for outline with no contours" do
      outline = described_class.new(
        glyph_id: 0,
        contours: [],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      expect(outline.empty?).to be true
    end

    it "returns false for outline with contours" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [{ x: 100, y: 0, on_curve: true }],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 100, y_max: 0 },
      )

      expect(outline.empty?).to be false
    end
  end

  describe "#point_count" do
    it "returns zero for empty outline" do
      outline = described_class.new(
        glyph_id: 0,
        contours: [],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      expect(outline.point_count).to eq(0)
    end

    it "returns correct count for single contour" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 200, y: 700, on_curve: true },
            { x: 300, y: 0, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )

      expect(outline.point_count).to eq(3)
    end

    it "returns correct count for multiple contours" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 200, y: 700, on_curve: true },
          ],
          [
            { x: 150, y: 200, on_curve: true },
            { x: 250, y: 200, on_curve: true },
            { x: 250, y: 400, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )

      expect(outline.point_count).to eq(5)
    end
  end

  describe "#contour_count" do
    it "returns zero for empty outline" do
      outline = described_class.new(
        glyph_id: 0,
        contours: [],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      expect(outline.contour_count).to eq(0)
    end

    it "returns correct count for multiple contours" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [{ x: 100, y: 0, on_curve: true }],
          [{ x: 150, y: 200, on_curve: true }],
          [{ x: 200, y: 300, on_curve: true }],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )

      expect(outline.contour_count).to eq(3)
    end
  end

  describe "#to_svg_path" do
    it "returns empty string for empty outline" do
      outline = described_class.new(
        glyph_id: 0,
        contours: [],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      expect(outline.to_svg_path).to eq("")
    end

    it "converts simple triangle to SVG path" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 200, y: 700, on_curve: true },
            { x: 300, y: 0, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )

      svg_path = outline.to_svg_path

      expect(svg_path).to start_with("M 100 0")
      expect(svg_path).to include("L 200 700")
      expect(svg_path).to include("L 300 0")
      expect(svg_path).to end_with("Z")
    end

    it "handles off-curve points with quadratic curves" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 150, y: 50, on_curve: false }, # control point
            { x: 200, y: 0, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 50 },
      )

      svg_path = outline.to_svg_path

      expect(svg_path).to include("M 100 0")
      expect(svg_path).to include("Q 150 50 200 0")
      expect(svg_path).to end_with("Z")
    end

    it "handles consecutive off-curve points with implied on-curve midpoint" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 120, y: 50, on_curve: false },
            { x: 180, y: 50, on_curve: false },
            { x: 200, y: 0, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 50 },
      )

      svg_path = outline.to_svg_path

      expect(svg_path).to include("M 100 0")
      expect(svg_path).to include("Q")
      expect(svg_path).to end_with("Z")
    end

    it "handles multiple contours" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 200, y: 700, on_curve: true },
            { x: 300, y: 0, on_curve: true },
          ],
          [
            { x: 150, y: 200, on_curve: true },
            { x: 250, y: 400, on_curve: true },
            { x: 250, y: 200, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )

      svg_path = outline.to_svg_path

      # Should have two separate paths, both starting with M and ending with Z
      expect(svg_path.scan("M").length).to eq(2)
      expect(svg_path.scan("Z").length).to eq(2)
    end
  end

  describe "#to_commands" do
    it "returns empty array for empty outline" do
      outline = described_class.new(
        glyph_id: 0,
        contours: [],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      expect(outline.to_commands).to eq([])
    end

    it "converts simple triangle to commands" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 200, y: 700, on_curve: true },
            { x: 300, y: 0, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )

      commands = outline.to_commands

      expect(commands).to eq([
                               [:move_to, 100, 0],
                               [:line_to, 200, 700],
                               [:line_to, 300, 0],
                               [:close_path],
                             ])
    end

    it "handles off-curve points with curve commands" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 150, y: 50, on_curve: false },
            { x: 200, y: 0, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 50 },
      )

      commands = outline.to_commands

      expect(commands[0]).to eq([:move_to, 100, 0])
      expect(commands[1]).to eq([:curve_to, 150, 50, 200, 0])
      expect(commands[2]).to eq([:close_path])
    end

    it "handles multiple contours" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 200, y: 0, on_curve: true },
          ],
          [
            { x: 150, y: 200, on_curve: true },
            { x: 250, y: 200, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )

      commands = outline.to_commands

      # Should have two move_to commands (one per contour)
      move_commands = commands.select { |cmd| cmd[0] == :move_to }
      expect(move_commands.length).to eq(2)

      # Should have two close_path commands
      close_commands = commands.select { |cmd| cmd[0] == :close_path }
      expect(close_commands.length).to eq(2)
    end
  end

  describe "#to_s and #inspect" do
    it "returns human-readable representation" do
      outline = described_class.new(
        glyph_id: 65,
        contours: [
          [
            { x: 100, y: 0, on_curve: true },
            { x: 200, y: 700, on_curve: true },
            { x: 300, y: 0, on_curve: true },
          ],
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )

      str = outline.to_s

      expect(str).to include("GlyphOutline")
      expect(str).to include("glyph_id=65")
      expect(str).to include("contours=1")
      expect(str).to include("points=3")

      expect(outline.inspect).to eq(str)
    end
  end
end
