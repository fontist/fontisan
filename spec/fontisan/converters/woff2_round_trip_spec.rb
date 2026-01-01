# frozen_string_literal: true

require "spec_helper"
require "fontisan/converters/woff2_encoder"
require "tempfile"

RSpec.describe "WOFF2 Round-Trip Validation", :woff2 do
  let(:encoder) { Fontisan::Converters::Woff2Encoder.new }

  # NOTE: These tests validate WOFF2 ENCODING only
  # Reading encoded WOFF2 files back is blocked by a critical issue
  # where table() returns nil. This will be fixed in Phase 1.2.4.
  # See docs/WOFF2_ENCODING_TEST_RESULTS.md for details.

  describe "TTF → WOFF2 encoding" do
    let(:original_font_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:original_font) { Fontisan::FontLoader.load(original_font_path) }

    it "successfully encodes TTF to WOFF2" do
      woff2_result = encoder.convert(original_font, transform_tables: true)
      woff2_binary = woff2_result[:woff2_binary]

      # Validate WOFF2 structure
      expect(woff2_binary).to be_a(String)
      expect(woff2_binary.bytesize).to be > 0
      expect(woff2_binary[0, 4]).to eq("wOF2")

      # Validate header fields
      io = StringIO.new(woff2_binary)
      signature = io.read(4)
      flavor = io.read(4).unpack1("N")
      length = io.read(4).unpack1("N")

      expect(signature).to eq("wOF2")
      expect(flavor).to eq(0x00010000) # TrueType
      expect(length).to eq(woff2_binary.bytesize)
    end

    it "writes valid WOFF2 files to disk" do
      woff2_result = encoder.convert(original_font, transform_tables: true)

      Tempfile.create(["write_test", ".woff2"]) do |woff2_file|
        File.binwrite(woff2_file.path, woff2_result[:woff2_binary])

        # File should exist and have correct size
        expect(File.exist?(woff2_file.path)).to be true
        expect(File.size(woff2_file.path)).to eq(woff2_result[:woff2_binary].bytesize)

        # File should have WOFF2 signature
        signature = File.binread(woff2_file.path, 4)
        expect(signature).to eq("wOF2")
      end
    end
  end

  describe "OTF → WOFF2 encoding" do
    let(:otf_path) { "spec/fixtures/fonts/MonaSans/mona-sans-2.0.8/fonts/static/otf/MonaSans-Regular.otf" }

    it "successfully encodes CFF fonts to WOFF2" do
      skip "OTF font not found" unless File.exist?(otf_path)

      original_font = Fontisan::FontLoader.load(otf_path)
      woff2_result = encoder.convert(original_font, transform_tables: true)

      # Validate structure
      expect(woff2_result[:woff2_binary][0, 4]).to eq("wOF2")

      # Verify flavor is 'OTTO' for CFF
      flavor = woff2_result[:woff2_binary][4, 4].unpack1("N")
      expect(flavor).to eq(0x4F54544F)
    end
  end

  describe "variable font encoding" do
    let(:vf_path) { "spec/fixtures/fonts/MonaSans/mona-sans-2.0.8/fonts/variable/MonaSansVF[wght,opsz].ttf" }

    it "successfully encodes variable fonts to WOFF2" do
      skip "Variable font not found" unless File.exist?(vf_path)

      original_font = Fontisan::FontLoader.load(vf_path)
      woff2_result = encoder.convert(original_font, transform_tables: true)

      # Validate structure
      expect(woff2_result[:woff2_binary][0, 4]).to eq("wOF2")

      # Should be TrueType flavor (variable fonts are TTF-based)
      flavor = woff2_result[:woff2_binary][4, 4].unpack1("N")
      expect(flavor).to eq(0x00010000)
    end
  end

  describe "compression consistency" do
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:font) { Fontisan::FontLoader.load(font_path) }

    it "produces deterministic output" do
      # Same input should always produce same output
      result1 = encoder.convert(font, transform_tables: true)
      result2 = encoder.convert(font, transform_tables: true)

      expect(result1[:woff2_binary]).to eq(result2[:woff2_binary])
    end

    it "respects Brotli quality settings" do
      low_quality = encoder.convert(font, transform_tables: true, quality: 0)
      high_quality = encoder.convert(font, transform_tables: true, quality: 11)

      # Both should be valid
      expect(low_quality[:woff2_binary][0, 4]).to eq("wOF2")
      expect(high_quality[:woff2_binary][0, 4]).to eq("wOF2")

      # Higher quality → better compression (smaller size)
      expect(high_quality[:woff2_binary].bytesize).to be <= low_quality[:woff2_binary].bytesize
    end

    it "achieves significant compression" do
      original_size = font.table_data.values.sum(&:bytesize)
      result = encoder.convert(font, transform_tables: true)
      woff2_size = result[:woff2_binary].bytesize

      compression_ratio = ((original_size - woff2_size).to_f / original_size * 100).round(2)

      # Should achieve at least 30% compression
      expect(compression_ratio).to be > 30.0

      # For reference: TestTTF achieves ~60% compression
      puts "\nCompression: #{compression_ratio}% (#{original_size} → #{woff2_size} bytes)"
    end
  end

  describe "structure validation" do
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:font) { Fontisan::FontLoader.load(font_path) }

    it "produces valid WOFF2 header structure" do
      result = encoder.convert(font, transform_tables: true)
      binary = result[:woff2_binary]

      io = StringIO.new(binary)
      signature = io.read(4)
      flavor = io.read(4).unpack1("N")
      length = io.read(4).unpack1("N")
      num_tables = io.read(2).unpack1("n")
      reserved = io.read(2).unpack1("n")
      total_sfnt_size = io.read(4).unpack1("N")
      total_compressed_size = io.read(4).unpack1("N")

      # Validate all header fields
      expect(signature).to eq("wOF2")
      expect([0x00010000, 0x4F54544F]).to include(flavor)
      expect(length).to eq(binary.bytesize)
      expect(num_tables).to be > 0
      expect(reserved).to eq(0)
      expect(total_sfnt_size).to be > 0
      expect(total_compressed_size).to be > 0
    end

    it "writes files with correct size" do
      result = encoder.convert(font, transform_tables: true)

      Tempfile.create(["size_test", ".woff2"]) do |woff2_file|
        File.binwrite(woff2_file.path, result[:woff2_binary])

        # Length field should match actual file size
        length_field = File.binread(woff2_file.path, 12)[8, 4].unpack1("N")
        actual_size = File.size(woff2_file.path)

        expect(length_field).to eq(actual_size)
      end
    end
  end
end