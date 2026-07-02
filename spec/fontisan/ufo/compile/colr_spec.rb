# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Colr do
  describe ".build" do
    it "returns nil for empty base_glyphs" do
      expect(described_class.build(base_glyphs: nil)).to be_nil
      expect(described_class.build(base_glyphs: [])).to be_nil
    end

    it "produces a valid COLR v0 header" do
      base_glyphs = [
        { gid: 0xE000, layers: [
          { layer_gid: 1, palette_index: 0 },
          { layer_gid: 2, palette_index: 1 },
        ] },
      ]
      bytes = described_class.build(base_glyphs: base_glyphs)
      version = bytes.unpack1("n")
      expect(version).to eq(0)
    end

    it "encodes the correct header fields" do
      base_glyphs = [
        { gid: 0xE000, layers: [{ layer_gid: 1, palette_index: 0 }] },
      ]
      bytes = described_class.build(base_glyphs: base_glyphs)
      version, num_base, base_offset, layer_offset, num_layers = bytes.unpack("nnNNn")
      expect(version).to eq(0)
      expect(num_base).to eq(1)
      expect(base_offset).to eq(14) # HEADER_SIZE
      expect(layer_offset).to eq(20) # 14 + 1 × 6
      expect(num_layers).to eq(1)
    end
  end
end
