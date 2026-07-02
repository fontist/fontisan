# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Colr do
  describe ".build" do
    it "returns nil for empty layers" do
      expect(described_class.build(layers: nil)).to be_nil
      expect(described_class.build(layers: [])).to be_nil
    end

    it "produces a valid COLR v0 header" do
      layers = [
        { gid: 0xE000, palette_index: 0, layer_gid: 1 },
      ]
      bytes = described_class.build(layers: layers)
      expect(bytes.unpack1("n")).to eq(0)
    end
  end
end
