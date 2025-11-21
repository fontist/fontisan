# frozen_string_literal: true

require "spec_helper"
require "fontisan/variable/glyph_delta_processor"
require "fontisan/tables/gvar"

RSpec.describe Fontisan::Variable::GlyphDeltaProcessor do
  let(:gvar_data) do
    # Build minimal gvar table data
    # For simplicity, we'll test the structure without actual variation data
    data = "".b
    data << [1, 0].pack("n2") # major, minor version
    data << [1].pack("n") # axis count
    data << [0].pack("n") # shared tuple count
    data << [20].pack("N") # shared tuples offset
    data << [2].pack("n") # glyph count
    data << [0].pack("n") # flags (not long offsets)
    data << [24].pack("N") # glyph variation data array offset

    # Offsets for 2 glyphs + 1 end (short offsets * 2)
    data << [0].pack("n") # glyph 0 offset
    data << [0].pack("n") # glyph 1 offset (no data)
    data << [0].pack("n") # end offset

    data
  end

  let(:gvar) { Fontisan::Tables::Gvar.read(gvar_data) }
  let(:processor) { described_class.new(gvar) }

  describe "#initialize" do
    it "creates processor with gvar table" do
      expect(processor).to be_a(described_class)
    end

    it "loads configuration" do
      expect(processor.config).to be_a(Hash)
    end
  end

  describe "#has_variations?" do
    it "returns false for glyph without variation data" do
      expect(processor.has_variations?(0)).to be false
    end

    it "returns false when gvar is nil" do
      nil_processor = described_class.new(nil)
      expect(nil_processor.has_variations?(0)).to be false
    end
  end

  describe "#glyph_count" do
    it "returns glyph count from gvar" do
      expect(processor.glyph_count).to eq(2)
    end

    it "returns 0 when gvar is nil" do
      nil_processor = described_class.new(nil)
      expect(nil_processor.glyph_count).to eq(0)
    end
  end

  describe "#apply_deltas" do
    let(:region_scalars) { [0.5, 1.0] }

    it "returns nil for glyph without variations" do
      result = processor.apply_deltas(0, region_scalars)
      expect(result).to be_nil
    end

    it "returns nil when gvar is nil" do
      nil_processor = described_class.new(nil)
      result = nil_processor.apply_deltas(0, region_scalars)
      expect(result).to be_nil
    end

    context "with glyph having variation data" do
      # This would require more complex gvar data setup
      # For now, we test the structure
      it "processes region scalars" do
        result = processor.apply_deltas(0, region_scalars)
        # Result should be nil because we have no actual variation data
        expect(result).to be_nil
      end
    end
  end

  describe "configuration" do
    it "respects apply_to_simple setting" do
      config = { glyph_deltas: { apply_to_simple: false } }
      processor_custom = described_class.new(gvar, config)
      expect(processor_custom.config[:glyph_deltas][:apply_to_simple]).to be false
    end

    it "respects process_phantom_points setting" do
      config = { glyph_deltas: { process_phantom_points: false } }
      processor_custom = described_class.new(gvar, config)
      expect(processor_custom.config[:glyph_deltas][:process_phantom_points]).to be false
    end

    it "uses default rounding mode" do
      expect(processor.config[:delta_application][:rounding_mode]).to eq("round")
    end
  end

  describe "edge cases" do
    it "handles nil region scalars" do
      expect { processor.apply_deltas(0, nil) }.not_to raise_error
    end

    it "handles empty region scalars" do
      result = processor.apply_deltas(0, [])
      expect(result).to be_nil
    end

    it "handles invalid glyph ID" do
      result = processor.apply_deltas(999, [0.5])
      expect(result).to be_nil
    end
  end
end
