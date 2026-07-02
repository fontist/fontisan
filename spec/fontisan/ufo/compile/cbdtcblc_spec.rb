# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::CbdtCblc do
  describe ".build" do
    it "returns nil for empty strikes" do
      expect(described_class.build(strikes: nil)).to be_nil
      expect(described_class.build(strikes: [])).to be_nil
    end

    it "produces both CBDT and CBLC tables" do
      png = "\x89PNG\r\n\x1a\n".b
      strikes = [{
        ppem: 16, resolution: 72,
        glyphs: [
          { origin_x: 0, origin_y: 0, data: png },
          nil,
        ]
      }]
      tables = described_class.build(strikes: strikes)
      expect(tables).to have_key("CBDT")
      expect(tables).to have_key("CBLC")
    end
  end
end
