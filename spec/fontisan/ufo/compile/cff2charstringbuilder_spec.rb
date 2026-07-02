# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff"

RSpec.describe Fontisan::Tables::Cff::Cff2CharStringBuilder do
  describe "operator table" do
    it "removes hmoveto (replaced by vsindex in CFF2)" do
      expect(described_class::OPERATORS_CFF2).not_to have_key(:hmoveto)
    end

    it "adds vsindex (22)" do
      expect(described_class::OPERATORS_CFF2[:vsindex]).to eq(22)
    end

    it "adds blend (23)" do
      expect(described_class::OPERATORS_CFF2[:blend]).to eq(23)
    end
  end

  describe ".build_variable" do
    let(:default_outline) do
      Fontisan::Models::Outline.new(
        glyph_id: 1,
        commands: [
          { type: :move_to, x: 0, y: 0 },
          { type: :line_to, x: 100, y: 0 },
          { type: :line_to, x: 100, y: 100 },
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 100, y_max: 100 },
      )
    end

    let(:bold_outline) do
      Fontisan::Models::Outline.new(
        glyph_id: 1,
        commands: [
          { type: :move_to, x: 0, y: 0 },
          { type: :line_to, x: 120, y: 0 },
          { type: :line_to, x: 120, y: 120 },
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 120, y_max: 120 },
      )
    end

    it "produces a non-empty charstring" do
      bytes = described_class.build_variable(
        default_outline,
        master_outlines: [bold_outline],
        num_regions: 1,
      )
      expect(bytes).not_to be_empty
    end

    it "includes blend operators (byte 23) for varying coordinates" do
      bytes = described_class.build_variable(
        default_outline,
        master_outlines: [bold_outline],
        num_regions: 1,
      )
      # The blend operator is byte 23 (0x17)
      expect(bytes.bytes).to include(23)
    end

    it "does not include blend when deltas are all zero" do
      # Same outline as default → no deltas
      bytes = described_class.build_variable(
        default_outline,
        master_outlines: [default_outline.dup],
        num_regions: 1,
      )
      # All deltas are zero → no blend operators
      expect(bytes.bytes).not_to include(23)
    end

    it "includes the endchar operator (byte 14)" do
      bytes = described_class.build_variable(
        default_outline,
        master_outlines: [bold_outline],
        num_regions: 1,
      )
      expect(bytes.bytes.last).to eq(14)
    end

    it "supports multiple masters" do
      light_outline = Fontisan::Models::Outline.new(
        glyph_id: 1,
        commands: [
          { type: :move_to, x: 0, y: 0 },
          { type: :line_to, x: 80, y: 0 },
          { type: :line_to, x: 80, y: 80 },
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 80, y_max: 80 },
      )

      bytes = described_class.build_variable(
        default_outline,
        master_outlines: [bold_outline, light_outline],
        num_regions: 2,
      )
      # Each varying coordinate has 2 deltas → blend with r=2
      expect(bytes.bytes).to include(23)
    end
  end
end
