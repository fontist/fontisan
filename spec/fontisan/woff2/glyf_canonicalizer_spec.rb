# frozen_string: true

require "spec_helper"

RSpec.describe Fontisan::Woff2::GlyfCanonicalizer do
  describe "#canonical" do
    it "preserves source glyph bytes verbatim" do
      # Two glyphs: [0x10, 0x20, 0x30] (3 bytes) and [0x40, 0x50] (2 bytes)
      glyf = "\x10\x20\x30\x40\x50".b
      # Long loca (indexFormat=1): byte offsets as uint32
      loca = [0, 3, 5].pack("N*")

      result = described_class.new(
        glyf_data: glyf,
        loca_data: loca,
        num_glyphs: 2,
        source_format: 1, # long
        target_format: 1, # long
      ).canonical

      # Each glyph padded to 4-byte boundary:
      # glyph 0: 3 bytes + 1 pad = 4 bytes (offset 0..3)
      # glyph 1: 2 bytes + 2 pad = 4 bytes (offset 4..7)
      expect(result[:glyf].bytes).to eq([0x10, 0x20, 0x30, 0, 0x40, 0x50, 0, 0])
      # Long loca entries: [0, 4, 8]
      expect(result[:loca].unpack("N*")).to eq([0, 4, 8])
    end

    it "preserves empty glyphs as zero-length" do
      # Two glyphs: first empty (0 bytes), second 2 bytes
      glyf = "\xAA\xBB".b
      loca = [0, 0, 2].pack("N*")

      result = described_class.new(
        glyf_data: glyf,
        loca_data: loca,
        num_glyphs: 2,
        source_format: 1,
        target_format: 1,
      ).canonical

      # Empty glyph contributes 0 bytes (no padding)
      # 2-byte glyph padded to 4 bytes
      expect(result[:glyf].bytes).to eq([0xAA, 0xBB, 0, 0])
    end

    it "emits loca in target_format when different from source" do
      glyf = "\x10\x20\x30".b
      # Long loca source: byte offsets 0, 3
      loca = [0, 3].pack("N*")

      result = described_class.new(
        glyf_data: glyf,
        loca_data: loca,
        num_glyphs: 1,
        source_format: 1, # long
        target_format: 0, # short
      ).canonical

      # 3-byte glyph padded to 4 bytes
      expect(result[:glyf].bytes).to eq([0x10, 0x20, 0x30, 0])
      # Short loca: 2 entries (num_glyphs+1), offset/2 as uint16
      # glyph 0 ends at offset 4, so loca = [0, 2]
      expect(result[:loca].unpack("n*")).to eq([0, 2])
    end

    it "raises when loca entry count mismatches num_glyphs + 1" do
      glyf = "".b
      loca = [0].pack("N*") # only 1 entry, but need 3 for 2 glyphs

      expect do
        described_class.new(
          glyf_data: glyf,
          loca_data: loca,
          num_glyphs: 2,
          source_format: 1,
        ).canonical
      end.to raise_error(Fontisan::InvalidFontError,
                         /loca has 1 entries, expected 3/)
    end

    it "matches fontTools' 4-byte-padded canonical form for a real font" do
      # Avestan source WOFF — known to require 4-byte padding for Chrome OTS.
      # fontTools' _normaliseGlyfAndLoca(padding=4) produces a 15916-byte glyf
      # from a 15844-byte source. We must produce the same.
      skip "avestan fixture missing" unless File.exist?(
        "/Users/mulgogi/src/essenfont/essenfont.github.io/public/fonts/avestan.woff",
      )

      font = Fontisan::FontLoader.load(
        "/Users/mulgogi/src/essenfont/essenfont.github.io/public/fonts/avestan.woff",
      )

      result = described_class.new(
        glyf_data: font.table_data["glyf"],
        loca_data: font.table_data["loca"],
        num_glyphs: font.table("maxp").num_glyphs,
        source_format: font.table("head").index_to_loc_format,
        target_format: 0,
      ).canonical

      # fontTools' padding=4 canonical glyf for avestan is 15916 bytes.
      # Anything else means we're re-encoding or padding incorrectly.
      expect(result[:glyf].bytesize).to eq(15916)
      expect(result[:loca].bytesize).to eq(126)
    end
  end
end
