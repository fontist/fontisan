# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Fontisan::Woff2::CollectionDecoder do
  let(:ttc_path) { fixture_path("fonts/DinaRemasterII/DinaRemasterII.ttc") }
  let(:fonts) do
    File.open(ttc_path, "rb") do |io|
      Fontisan::FontLoader.load_collection(ttc_path).extract_fonts(io)
    end
  end
  let(:woff2_bytes) do
    Fontisan::Woff2::CollectionEncoder.new(brotli_quality: 11).encode_fonts(fonts)
  end

  let(:decoder) { described_class.new(woff2_bytes) }

  describe "#decode" do
    subject(:result) { decoder.decode }

    it "returns one entry per source font" do
      expect(result.length).to eq(fonts.length)
    end

    it "each entry has :flavor and :tables keys" do
      expect(result).to all(include(:flavor, :tables))
    end

    it "flavor matches the source fonts" do
      result.each_with_index do |entry, _i|
        expect(entry[:flavor]).to eq(Fontisan::Constants::SFNT_VERSION_TRUETYPE)
      end
    end

    it "tables hash contains glyf and loca per font" do
      result.each do |entry|
        expect(entry[:tables]).to include("glyf", "loca")
      end
    end

    it "reconstructs glyf to a non-empty binary string" do
      result.each do |entry|
        glyf = entry[:tables]["glyf"]
        expect(glyf).to be_a(String)
        expect(glyf.bytesize).to be > 0
      end
    end

    it "raises InvalidFontError for non-WOFF2 input" do
      expect { described_class.new("not a woff2").decode }
        .to raise_error(Fontisan::InvalidFontError, /Invalid WOFF2 signature/)
    end

    it "raises InvalidFontError for a single-font WOFF2 (flavor not 'ttcf')" do
      skip "needs a single-font WOFF2 fixture" unless File.exist?(fixture_path("fonttools/TestWOFF2.woff2"))

      single_bytes = File.binread(fixture_path("fonttools/TestWOFF2.woff2"))
      expect { described_class.new(single_bytes).decode }
        .to raise_error(Fontisan::InvalidFontError, /not a collection/)
    end
  end
end
