# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Sbix do
  describe ".build" do
    it "returns nil for no strikes" do
      expect(described_class.build(strikes: nil, num_glyphs: 2)).to be_nil
      expect(described_class.build(strikes: [], num_glyphs: 2)).to be_nil
    end

    it "produces a valid sbix header" do
      png = "\x89PNG\r\n\x1a\n".b + "\x00" * 20
      strikes = [{
        ppem: 20, resolution: 72,
        glyphs: [{ origin_x: 0, origin_y: 0, graphic_type: "png ", data: png }]
      }]
      bytes = described_class.build(strikes: strikes, num_glyphs: 2)
      version, = bytes.unpack("n")
      expect(version).to eq(1)
    end

    it "embeds PNG data in the strike" do
      png = "\x89PNG\r\n\x1a\n".b + "\x00" * 10
      strikes = [{
        ppem: 32, resolution: 72,
        glyphs: [
          { origin_x: 0, origin_y: 0, graphic_type: "png ", data: png },
          nil,
        ]
      }]
      bytes = described_class.build(strikes: strikes, num_glyphs: 2)
      expect(bytes).to include(png)
      expect(bytes).to include("png ")
    end
  end
end
