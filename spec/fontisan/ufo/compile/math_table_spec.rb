# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::MathTable do
  describe ".build" do
    it "returns nil when no data provided" do
      expect(described_class.build).to be_nil
    end

    it "produces a valid MATH header with version 1.0" do
      bytes = described_class.build(constants: { axisHeight: 250 })
      version = bytes[0, 4].unpack1("N")
      expect(version).to eq(0x00010000)
    end

    it "encodes all 54 constant values" do
      bytes = described_class.build(constants: { axisHeight: 250 })
      expect(bytes.bytesize).to be >= 10 + (54 * 2)
    end

    it "places provided constants at the correct position" do
      bytes = described_class.build(constants: { axisHeight: 250 })
      constants_offset = bytes[4, 2].unpack1("n")
      axis_height = bytes[constants_offset + 10, 2].unpack1("s>")
      expect(axis_height).to eq(250)
    end
  end
end
