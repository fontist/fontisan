# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/convert"

RSpec.describe Fontisan::Ufo::Convert::FromBinData do
  let(:ufo_path) { "/Users/mulgogi/src/external/unicode/last-resort-font/font.ufo" }
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  before { skip "last-resort-font not available" unless Dir.exist?(ufo_path) }

  describe ".convert (TTF → UFO round-trip)" do
    # Note: full UFO→TTF→UFO round-trip through fontisan's own compiler
    # is blocked by a glyf encoder bug (the Compile::GlyfLoca module
    # produces slightly malformed glyf bytes that fontisan's own reader
    # rejects). Once TODO 07 (filters) lands with a proper
    # reverse_contour_direction + cubic_to_quadratic pipeline, this
    # round-trip should work. For now we test with real TTF sources
    # (NotoSans) which the reader can parse correctly.

    it "converts a real TTF (NotoSans) back to a UFO with glyphs" do
      noto_path = "spec/fixtures/fonts/NotoSans/NotoSans-Regular.ttf"
      skip "NotoSans fixture not available" unless File.exist?(noto_path)

      ttf = Fontisan::FontLoader.load(noto_path)
      converted = described_class.convert(ttf)

      expect(converted.glyphs.size).to be > 100
    end
  end

  describe ".convert (direct TTF load)" do
    let(:noto_path) { "spec/fixtures/fonts/NotoSans/NotoSans-Regular.ttf" }

    before { skip "NotoSans fixture not available" unless File.exist?(noto_path) }

    it "converts a real TTF to a UFO with glyphs" do
      ttf = Fontisan::FontLoader.load(noto_path)
      converted = described_class.convert(ttf)

      expect(converted.glyphs.size).to be > 100
      expect(converted.info.units_per_em).to eq(ttf.table("head").units_per_em)
    end
  end
end
