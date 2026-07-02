# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::SvgTable do
  describe ".build" do
    it "returns nil for nil entries" do
      expect(described_class.build(entries: nil)).to be_nil
    end

    it "returns nil for empty entries" do
      expect(described_class.build(entries: [])).to be_nil
    end

    it "produces a valid SVG header" do
      svg = "<svg/>"
      bytes = described_class.build(entries: [{ start_gid: 0, end_gid: 0, svg: svg }])
      version, doc_list_offset, reserved = bytes.unpack("nNN")
      expect(version).to eq(0)
      expect(doc_list_offset).to eq(10)
      expect(reserved).to eq(0)
    end

    it "embeds SVG document data after the records" do
      svg = "<svg/>"
      bytes = described_class.build(entries: [{ start_gid: 0, end_gid: 0, svg: svg }])
      expect(bytes).to include(svg)
    end
  end
end
