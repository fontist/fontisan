# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Fontisan::Woff2::GlyfLocaReconstruct do
  let(:input_ttf) { fixture_path("fonttools/TestTTF.ttf") }
  let(:font) { Fontisan::FontLoader.load(input_ttf) }
  let(:num_glyphs) { font.table("maxp").num_glyphs }
  let(:index_format) { font.table("head").index_to_loc_format }
  let(:orig_glyf) { font.table_data["glyf"] }
  let(:orig_loca) { font.table_data["loca"] }

  # Build a transformed glyf table from the input font via the encoder's
  # transform. This is the input to the reconstruct.
  let(:transformed_glyf) do
    Fontisan::Woff2::GlyfLocaTransform.new(
      glyf_data: orig_glyf,
      loca_data: orig_loca,
      num_glyphs:,
      index_format:,
    ).transform
  end

  let(:reconstructor) do
    described_class.new(transformed_glyf:, num_glyphs:, index_format:)
  end

  describe "#reconstruct" do
    subject(:result) { reconstructor.reconstruct }

    it "returns a Hash with :glyf and :loca keys" do
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(:glyf, :loca)
    end

    it "returns binary strings" do
      expect(result[:glyf]).to be_a(String)
      expect(result[:glyf].encoding).to eq(Encoding::BINARY)
      expect(result[:loca]).to be_a(String)
      expect(result[:loca].encoding).to eq(Encoding::BINARY)
    end

    it "produces a loca table with the right size for the indexFormat" do
      # loca size = (numGlyphs + 1) × 2 (short) or × 4 (long)
      expected_size = (num_glyphs + 1) * (index_format.zero? ? 2 : 4)
      expect(result[:loca].bytesize).to eq(expected_size)
    end

    it "decodes glyphs with semantically equivalent outlines", :python do
      skip "fontTools not available" unless python_fonttools?

      Dir.mktmpdir do |dir|
        # Round-trip through the encoder → decoder to validate.
        woff2 = Fontisan::Converters::Woff2Encoder.new
          .convert(font, brotli_quality: 11)[:woff2_binary]
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        decoded = Fontisan::Woff2Font.from_file(path)
        decoded.table_data["glyf"]

        # Both fonts should have the same glyphs in the same order, with
        # matching numberOfContours per glyph. We use fontTools to compare
        # coordinates since the binary representation may legitimately
        # differ per OFF section 5.3.3.
        script = File.join(dir, "compare.py")
        File.write(script, <<~PY)
          import sys
          from fontTools.ttLib import TTFont
          a = TTFont(sys.argv[1])["glyf"]
          b = TTFont(sys.argv[2])["glyf"]
          for name in sys.argv[3].split(","):
              ga = a[name]
              gb = b[name]
              assert ga.numberOfContours == gb.numberOfContours, name
              if ga.numberOfContours > 0:
                  assert list(ga.coordinates) == list(gb.coordinates), name
          print("OK")
        PY
        names = font_rescue_glyph_names
        output = `python3 #{script} #{input_ttf} #{path} #{names.join(",")} 2>&1`
        expect($?).to be_success,
                      "fontTools glyph comparison failed:\n#{output}"
      end
    end

    it "decodes fontTools' WOFF2 output successfully", :python do
      skip "fontTools not available" unless python_fonttools?

      Dir.mktmpdir do |dir|
        ft_woff2 = File.join(dir, "ft.woff2")
        script = File.join(dir, "encode.py")
        File.write(script, <<~PY)
          import io
          from fontTools.ttLib import TTFont
          t = TTFont("#{input_ttf}")
          out = io.BytesIO()
          t.flavor = "woff2"
          t.save(out)
          open("#{ft_woff2}", "wb").write(out.getvalue())
        PY
        system("python3 #{script}")
        decoded = Fontisan::Woff2Font.from_file(ft_woff2)
        expect(decoded.table_data["glyf"]).not_to be_empty
        expect(decoded.table_data["loca"]).not_to be_empty
      end
    end
  end

  # Helper: extract glyph names from the source font for the comparison.
  def font_rescue_glyph_names
    # TestTTF.ttf has these 6 well-known glyphs in order.
    %w[.notdef .null CR space period ellipsis]
  end
end
