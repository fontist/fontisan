# frozen_string_literal: true

require "spec_helper"
require "fontisan/validation/woff2_validator"
require "fontisan/validation/woff2_header_validator"
require "fontisan/validation/woff2_table_validator"

RSpec.describe Fontisan::Validation::Woff2Validator do
  let(:rules) do
    {
      "woff2_validation" => {
        "min_compression_ratio" => 0.2,
        "max_compression_ratio" => 0.95,
        "max_table_size" => 104_857_600,
      },
    }
  end

  describe "#initialize" do
    it "accepts valid validation levels" do
      expect { described_class.new(level: :strict) }.not_to raise_error
      expect { described_class.new(level: :standard) }.not_to raise_error
      expect { described_class.new(level: :lenient) }.not_to raise_error
    end

    it "rejects invalid validation levels" do
      expect { described_class.new(level: :invalid) }.to raise_error(ArgumentError, /Invalid validation level/)
    end

    it "uses standard level by default" do
      validator = described_class.new
      expect(validator.level).to eq(:standard)
    end
  end

  describe "#validate" do
    let(:validator) { described_class.new }
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:woff2_path) { fixture_path("woff2/test.woff2") }

    context "with valid WOFF2 font" do
      it "validates successfully" do
        # Encode a font to WOFF2 first
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        # Save and reload as WOFF2
        temp_path = File.join(Dir.tmpdir, "test_valid.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        report = validator.validate(woff2_font, temp_path)

        # Debug: print report if it fails
        unless report.valid
          puts "\n=== Validation Report ==="
          puts report.text_summary
          puts "========================\n"
        end

        expect(report.valid).to be true
        expect(report.errors).to be_empty

        File.unlink(temp_path) if File.exist?(temp_path)
      end

      it "reports compression info" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_compression.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        report = validator.validate(woff2_font, temp_path)

        # Should have compression info (use info_issues not info)
        compression_info = report.info_issues.find { |i| i.category == "woff2_compression" }
        expect(compression_info).not_to be_nil
        expect(compression_info.message).to include("Compression ratio:")

        File.unlink(temp_path) if File.exist?(temp_path)
      end
    end

    context "validation levels" do
      let(:font) { Fontisan::FontLoader.load(font_path, mode: :full) }
      let(:encoder) { Fontisan::Converters::Woff2Encoder.new }

      it "strict level rejects warnings" do
        result = encoder.convert(font, transform_tables: true)
        temp_path = File.join(Dir.tmpdir, "test_strict.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)

        strict_validator = described_class.new(level: :strict)
        report = strict_validator.validate(woff2_font, temp_path)

        # Strict requires no warnings
        if report.has_warnings?
          expect(report.valid).to be false
        else
          expect(report.valid).to be true
        end

        File.unlink(temp_path) if File.exist?(temp_path)
      end

      it "standard level allows warnings" do
        result = encoder.convert(font, transform_tables: true)
        temp_path = File.join(Dir.tmpdir, "test_standard.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)

        standard_validator = described_class.new(level: :standard)
        report = standard_validator.validate(woff2_font, temp_path)

        # Standard allows warnings but not errors
        expect(report.valid).to eq(!report.has_errors?)

        File.unlink(temp_path) if File.exist?(temp_path)
      end
    end
  end
end

RSpec.describe Fontisan::Validation::Woff2HeaderValidator do
  let(:rules) do
    {
      "woff2_validation" => {
        "min_compression_ratio" => 0.2,
        "max_compression_ratio" => 0.95,
      },
    }
  end
  let(:validator) { described_class.new(rules) }

  describe "#validate" do
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }

    context "valid header" do
      it "passes validation with correct signature" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_header.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        issues = validator.validate(woff2_font)

        signature_errors = issues.select { |i| i[:message].include?("signature") && i[:severity] == "error" }
        expect(signature_errors).to be_empty

        File.unlink(temp_path) if File.exist?(temp_path)
      end

      it "validates flavor correctly" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_flavor.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        issues = validator.validate(woff2_font)

        flavor_errors = issues.select { |i| i[:message].include?("flavor") && i[:severity] == "error" }
        expect(flavor_errors).to be_empty

        File.unlink(temp_path) if File.exist?(temp_path)
      end

      it "validates table count consistency" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_count.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        issues = validator.validate(woff2_font)

        count_errors = issues.select { |i| i[:message].include?("count") && i[:severity] == "error" }
        expect(count_errors).to be_empty

        File.unlink(temp_path) if File.exist?(temp_path)
      end

      it "validates compression ratio" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_ratio.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        issues = validator.validate(woff2_font)

        # Should have reasonable compression ratio
        ratio_warnings = issues.select { |i| i[:message].include?("Compression ratio") && i[:severity] == "warning" }
        # Good compression shouldn't trigger warnings
        expect(ratio_warnings).to be_empty

        File.unlink(temp_path) if File.exist?(temp_path)
      end
    end

    context "invalid header" do
      it "detects missing num_tables" do
        # Create a real WOFF2 font first, then mock specific checks
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_invalid.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)

        # Mock the header to have zero tables
        allow(woff2_font.header).to receive(:num_tables).and_return(0)

        issues = validator.validate(woff2_font)

        zero_tables_error = issues.find { |i| i[:message].include?("cannot be zero") }
        expect(zero_tables_error).not_to be_nil
        expect(zero_tables_error[:severity]).to eq("error")

        File.unlink(temp_path) if File.exist?(temp_path)
      end

      it "detects table count mismatch" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_mismatch.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)

        # Mock to claim different number of tables
        actual_count = woff2_font.table_entries.length
        allow(woff2_font.header).to receive(:num_tables).and_return(actual_count + 5)

        issues = validator.validate(woff2_font)

        mismatch_error = issues.find { |i| i[:message].include?("count mismatch") }
        expect(mismatch_error).not_to be_nil
        expect(mismatch_error[:severity]).to eq("error")

        File.unlink(temp_path) if File.exist?(temp_path)
      end
    end
  end
end

RSpec.describe Fontisan::Validation::Woff2TableValidator do
  let(:rules) do
    {
      "woff2_validation" => {
        "max_table_size" => 104_857_600,
      },
    }
  end
  let(:validator) { described_class.new(rules) }

  describe "#validate" do
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }

    context "valid tables" do
      it "validates table tags" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_tags.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        issues = validator.validate(woff2_font)

        tag_errors = issues.select { |i| i[:message].include?("tag") && i[:severity] == "error" }
        expect(tag_errors).to be_empty

        File.unlink(temp_path) if File.exist?(temp_path)
      end

      it "validates transformation flags" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_transform.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        issues = validator.validate(woff2_font)

        # Should have proper transformation flags
        transform_errors = issues.select do |i|
          i[:message].include?("transform") && i[:severity] == "error"
        end
        expect(transform_errors).to be_empty

        File.unlink(temp_path) if File.exist?(temp_path)
      end

      it "validates table sizes" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_sizes.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        issues = validator.validate(woff2_font)

        size_errors = issues.select { |i| i[:message].include?("length") && i[:severity] == "error" }
        expect(size_errors).to be_empty

        File.unlink(temp_path) if File.exist?(temp_path)
      end

      it "detects no duplicate tables" do
        font = Fontisan::FontLoader.load(font_path, mode: :full)
        encoder = Fontisan::Converters::Woff2Encoder.new
        result = encoder.convert(font, transform_tables: true)

        temp_path = File.join(Dir.tmpdir, "test_duplicates.woff2")
        File.binwrite(temp_path, result[:woff2_binary])

        woff2_font = Fontisan::Woff2Font.from_file(temp_path)
        issues = validator.validate(woff2_font)

        duplicate_errors = issues.select { |i| i[:message].include?("Duplicate") }
        expect(duplicate_errors).to be_empty

        File.unlink(temp_path) if File.exist?(temp_path)
      end
    end

    context "invalid tables" do
      it "detects duplicate table tags" do
        # Create mock font with duplicate tables
        woff2_font = instance_double(Fontisan::Woff2Font)
        entry1 = instance_double(Fontisan::Woff2TableDirectoryEntry)
        entry2 = instance_double(Fontisan::Woff2TableDirectoryEntry)

        allow(entry1).to receive_messages(tag: "head", flags: 1, orig_length: 100, transform_length: nil)

        allow(entry2).to receive_messages(tag: "head", flags: 1, orig_length: 100, transform_length: nil)

        allow(woff2_font).to receive(:table_entries).and_return([entry1, entry2])

        issues = validator.validate(woff2_font)

        duplicate_error = issues.find { |i| i[:message].include?("Duplicate") }
        expect(duplicate_error).not_to be_nil
        expect(duplicate_error[:severity]).to eq("error")
      end
    end
  end
end
