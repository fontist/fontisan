# frozen_string_literal: true

require "spec_helper"
require "fontisan/converters/conversion_strategy"
require "fontisan/converters/table_copier"
require "fontisan/converters/outline_converter"
require "fontisan/converters/woff_writer"
require "fontisan/converters/woff2_encoder"

RSpec.describe Fontisan::Converters::ConversionStrategy do
  describe "strategy DSL — declared options" do
    it "WoffWriter declares zlib/uncompressed/threshold/metadata/private" do
      names = Fontisan::Converters::WoffWriter.supported_options.map(&:name)
      expect(names).to eq(%i[zlib_level uncompressed compression_threshold
                             metadata_xml private_data])
    end

    it "Woff2Encoder declares brotli_quality and transform_tables" do
      names = Fontisan::Converters::Woff2Encoder.supported_options.map(&:name)
      expect(names).to eq(%i[brotli_quality transform_tables])
    end

    it "TableCopier declares no options" do
      expect(Fontisan::Converters::TableCopier.supported_options).to eq([])
    end

    it "Option struct exposes cli, desc, default for help generation" do
      zlib = Fontisan::Converters::WoffWriter.option_for(:zlib_level)
      expect(zlib).not_to be_nil
      expect(zlib.cli).to eq("--zlib-level=N")
      expect(zlib.desc).to include("zlib")
      expect(zlib.default).to eq(6)
      expect(zlib.range).to eq(0..9)
    end
  end

  describe ".default_options" do
    it "returns the declared defaults as a hash" do
      defaults = Fontisan::Converters::WoffWriter.default_options
      expect(defaults[:zlib_level]).to eq(6)
      expect(defaults[:uncompressed]).to be(false)
      expect(defaults[:compression_threshold]).to eq(100)
    end

    it "Woff2Encoder defaults brotli_quality to 11" do
      defaults = Fontisan::Converters::Woff2Encoder.default_options
      expect(defaults[:brotli_quality]).to eq(11)
      expect(defaults[:transform_tables]).to be(false)
    end
  end

  describe ".validate_options!" do
    it "TableCopier rejects zlib_level" do
      expect do
        Fontisan::Converters::TableCopier.validate_options!({ zlib_level: 9 })
      end.to raise_error(ArgumentError, /Unknown option/)
    end

    it "WoffWriter rejects out-of-range zlib_level" do
      expect do
        Fontisan::Converters::WoffWriter.validate_options!({ zlib_level: 99 })
      end.to raise_error(ArgumentError, /zlib_level/)
    end

    it "Woff2Encoder rejects zlib_level (cross-format misuse)" do
      expect do
        Fontisan::Converters::Woff2Encoder.validate_options!({ zlib_level: 9 })
      end.to raise_error(ArgumentError, /Unknown option/)
    end

    it "Woff2Encoder rejects out-of-range brotli_quality" do
      expect do
        Fontisan::Converters::Woff2Encoder.validate_options!({ brotli_quality: 99 })
      end.to raise_error(ArgumentError, /brotli_quality/)
    end

    it "WoffWriter accepts in-range zlib_level" do
      expect do
        Fontisan::Converters::WoffWriter.validate_options!({ zlib_level: 9 })
      end.not_to raise_error
    end

    it "Woff2Encoder accepts in-range brotli_quality" do
      expect do
        Fontisan::Converters::Woff2Encoder.validate_options!({ brotli_quality: 5 })
      end.not_to raise_error
    end

    it "rejects wrong-typed values" do
      expect do
        Fontisan::Converters::WoffWriter.validate_options!({ zlib_level: "fast" })
      end.to raise_error(ArgumentError, /zlib_level/)
    end

    it "rejects wrong-typed boolean" do
      expect do
        Fontisan::Converters::WoffWriter.validate_options!({ uncompressed: "yes" })
      end.to raise_error(ArgumentError, /uncompressed/)
    end
  end

  describe "FormatConverter.all_strategy_option_names" do
    it "unions option names across all strategies" do
      names = Fontisan::Converters::FormatConverter.all_strategy_option_names
      expect(names).to include(:zlib_level, :brotli_quality, :transform_tables,
                               :uncompressed, :compression_threshold)
    end
  end

  describe "FormatConverter.validate_options_for_target!" do
    it "passes zlib_level for :woff target" do
      expect do
        Fontisan::Converters::FormatConverter.validate_options_for_target!(
          :woff, { zlib_level: 9 }
        )
      end.not_to raise_error
    end

    it "rejects brotli_quality for :woff target (cross-format misuse)" do
      expect do
        Fontisan::Converters::FormatConverter.validate_options_for_target!(
          :woff, { brotli_quality: 5 }
        )
      end.to raise_error(ArgumentError, /do not apply.*woff/)
    end

    it "rejects zlib_level for :woff2 target (cross-format misuse)" do
      expect do
        Fontisan::Converters::FormatConverter.validate_options_for_target!(
          :woff2, { zlib_level: 9 }
        )
      end.to raise_error(ArgumentError, /do not apply.*woff2/)
    end

    it "passes brotli_quality for :woff2 target" do
      expect do
        Fontisan::Converters::FormatConverter.validate_options_for_target!(
          :woff2, { brotli_quality: 5 }
        )
      end.not_to raise_error
    end
  end
end
