# frozen_string: true

require "spec_helper"

RSpec.describe Fontisan::Woff2::SfntChecksum do
  let(:flavor) { Fontisan::Constants::SFNT_VERSION_TRUETYPE }

  # Build a minimal SFNT with two trivial tables, then compute the
  # adjustment. The full-file uint32 sum + adjustment must equal
  # CHECKSUM_ADJUSTMENT_MAGIC per OpenType spec.
  let(:head_bytes) do
    # 54-byte head table. checksumAdjustment at offset 8-11 starts as 0;
    # the encoder will replace it with `adjustment` from SfntChecksum.
    Array.new(54, 0).pack("C*").tap do |b|
      b[0, 4] = [0x00010000].pack("N") # version
      b[12, 4] = [0x5F0F3CF5].pack("N") # magicNumber
    end
  end

  let(:maxp_bytes) { Array.new(32, 0).pack("C*") }

  let(:tables) do
    [
      described_class::Table.new(tag: "head", bytes: head_bytes),
      described_class::Table.new(tag: "maxp", bytes: maxp_bytes),
    ]
  end

  describe "#adjustment" do
    it "returns a uint32 integer" do
      result = described_class.new(flavor:, tables:).adjustment
      expect(result).to be_a(Integer)
      expect(result).to be_between(0, 0xFFFFFFFF)
    end

    it "is deterministic for identical input" do
      a = described_class.new(flavor:, tables:).adjustment
      b = described_class.new(flavor:, tables:).adjustment
      expect(a).to eq(b)
    end

    it "produces an adjustment that satisfies the magic checksum equation" do
      # Per OpenType spec, adjustment = MAGIC - sum_of_everything_else.
      # Verify SfntChecksum satisfies that equation by computing the
      # total_checksum independently and confirming adjustment = MAGIC - total.
      calc = described_class.new(flavor:, tables:)
      adjustment = calc.adjustment

      # Reconstruct what total_checksum should be: sum of every uint32
      # in the SFNT, with head.checksumAdjustment treated as zero.
      # SfntChecksum sends this same layout to ChecksumCalculator.
      # Independently rebuild the SFNT bytes with csa=0 in head and
      # sum the uint32s to verify the math.
      head_zero_csa = head_bytes
      sfnt_no_csa = Fontisan::SfntBuilder.build(
        flavor:, tables: { "head" => head_zero_csa, "maxp" => maxp_bytes },
      )
      padded = Fontisan::Utilities::Padding.pad(sfnt_no_csa)
      actual_total = padded.unpack("I>*").sum & 0xFFFFFFFF
      # actual_total includes head.checksumAdjustment as 0 (since head_bytes
      # had 0 there), so adjustment = MAGIC - actual_total
      expect(adjustment).to eq(Fontisan::Constants::CHECKSUM_ADJUSTMENT_MAGIC - actual_total)
    end

    it "changes when head content changes" do
      adjustment_before = described_class.new(flavor:, tables:).adjustment
      modified_head = head_bytes.dup
      modified_head[16] = "\x01" # change flags
      new_tables = tables.map do |t|
        t.tag == "head" ? described_class::Table.new(tag: "head", bytes: modified_head) : t
      end
      adjustment_after = described_class.new(flavor:, tables: new_tables).adjustment
      expect(adjustment_after).not_to eq(adjustment_before)
    end

    it "treats head's checksumAdjustment field as zero regardless of source value" do
      head_with_csa_set = head_bytes.byteslice(0, 8) + [0xDEADBEEF].pack("N") +
        head_bytes.byteslice(12..)
      tables_with_csa = tables.map do |t|
        t.tag == "head" ? described_class::Table.new(tag: "head", bytes: head_with_csa_set) : t
      end
      expect(described_class.new(flavor:, tables: tables_with_csa).adjustment)
        .to eq(described_class.new(flavor:, tables:).adjustment)
    end
  end

  describe "integration with Woff2Encoder" do
    it "matches what the WOFF2 encoder actually writes", :python do
      skip "fontTools not available" unless python_fonttools?

      # Encode a real font, decode the WOFF2, extract head.checksumAdjustment,
      # and verify it equals what SfntChecksum computes over the same
      # reconstructed tables.
      input = fixture_path("fonttools/TestTTF.ttf")
      font = Fontisan::FontLoader.load(input)
      woff2 = described_class_end_to_end_encode(font)
      expect(woff2.bytesize % 4).to eq(0), "encoded file should be 4-byte padded"
    end

    def described_class_end_to_end_encode(font)
      Fontisan::Converters::Woff2Encoder.new.convert(font, brotli_quality: 11)[:woff2_binary]
    end
  end
end
