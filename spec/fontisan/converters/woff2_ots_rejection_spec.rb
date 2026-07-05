# frozen_string_literal: true

# Specs for the WOFF2 OTS rejection bug.
#
# Chrome's OpenType Sanitizer (OTS) rejects WOFF2 files that include a
# DSIG table or that fail to set head.flags bit 11. Per WOFF2 spec
# section 5:
#
#   "The compliant WOFF2 encoder MUST remove the DSIG table from an
#    input font data, prior to applying transformations and entropy
#    coding steps."
#
#   "The WOFF 2.0 encoders MUST also set bit 11 of the 'flags' field
#    of the head table ... to indicate that a recreated font file was
#    subjected to lossless modifying transform."

require "spec_helper"
require "tmpdir"

RSpec.describe Fontisan::Converters::Woff2Encoder do
  let(:input_ttf) { fixture_path("fonttools/TestTTF.ttf") }

  def encode_to_woff2(path)
    font = Fontisan::FontLoader.load(path)
    described_class.new.convert(font, brotli_quality: 11)[:woff2_binary]
  end

  describe "WOFF2 spec conformance" do
    it "removes the DSIG table" do
      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        font = Fontisan::Woff2Font.from_file(path)
        tags = font.table_entries.map(&:tag)
        expect(tags).not_to include("DSIG"),
                            "WOFF2 still contains a DSIG table directory entry; " \
                            "Woff2::EncoderRules must drop DSIG per WOFF2 spec section 5"
      end
    end

    it "sets head.flags bit 11 (FLAG_LOSSLESS_MODIFYING) on the encoded font" do
      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        head = Fontisan::Woff2Font.from_file(path).table("head")
        expect(head.flags & Fontisan::Tables::Head::FLAG_LOSSLESS_MODIFYING)
          .to be_nonzero,
              "head.flags bit 11 not set; Woff2::EncoderRules must mark the " \
              "head table to satisfy Chrome OTS and WOFF2 spec section 5"
      end
    end

    it "preserves head.flags bits other than bit 11" do
      font = Fontisan::FontLoader.load(input_ttf)
      original_flags = font.table("head").flags
      mask = ~Fontisan::Tables::Head::FLAG_LOSSLESS_MODIFYING

      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        encoded_flags = Fontisan::Woff2Font.from_file(path).table("head").flags
        expect(encoded_flags & mask).to eq(original_flags & mask),
                                        "head.flags bits other than bit 11 must be preserved verbatim"
      end
    end

    it "produces a WOFF2 that Python's fontTools can decode", :python do
      skip "fontTools not available" unless python_fonttools?

      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        # Pass path via argv (not string interpolation) so unusual paths
        # cannot break the script.
        script = <<~PY
          import sys
          from fontTools.ttLib import TTFont
          f = TTFont(sys.argv[1])
          print(sorted(f.keys()))
        PY
        output = `python3 -c '#{script.gsub("'", %q(\\\'))}' "#{path}" 2>&1`
        expect($?).to be_success,
                      "fontTools failed to parse WOFF2 output:\n#{output}"
        expect(output).to include("head"), "head table missing from WOFF2"
      end
    end
  end
end
