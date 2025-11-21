# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Collection::Builder do
  let(:font1) do
    double(
      "font1",
      table_names: %w[head hhea maxp],
      table_data: {
        "head" => "head_1",
        "hhea" => "shared",
        "maxp" => "maxp_1",
      },
      header: double("header", sfnt_version: 0x00010000),
      respond_to?: true,
    ).tap do |f|
      allow(f).to receive(:has_table?).with("head").and_return(true)
      allow(f).to receive(:has_table?).with("hhea").and_return(true)
      allow(f).to receive(:has_table?).with("maxp").and_return(true)
    end
  end

  let(:font2) do
    double(
      "font2",
      table_names: %w[head hhea maxp],
      table_data: {
        "head" => "head_2",
        "hhea" => "shared",
        "maxp" => "maxp_2",
      },
      header: double("header", sfnt_version: 0x00010000),
      respond_to?: true,
    ).tap do |f|
      allow(f).to receive(:has_table?).with("head").and_return(true)
      allow(f).to receive(:has_table?).with("hhea").and_return(true)
      allow(f).to receive(:has_table?).with("maxp").and_return(true)
    end
  end

  let(:fonts) { [font1, font2] }

  describe "#initialize" do
    it "initializes with fonts array" do
      builder = described_class.new(fonts)
      expect(builder).to be_a(described_class)
      expect(builder.fonts).to eq(fonts)
    end

    it "sets default format to ttc" do
      builder = described_class.new(fonts)
      expect(builder.format).to eq(:ttc)
    end

    it "accepts format option" do
      builder = described_class.new(fonts, format: :otc)
      expect(builder.format).to eq(:otc)
    end

    it "sets optimize to true by default" do
      builder = described_class.new(fonts)
      expect(builder.optimize).to be true
    end

    it "accepts optimize option" do
      builder = described_class.new(fonts, optimize: false)
      expect(builder.optimize).to be false
    end

    it "raises error when fonts is nil" do
      expect do
        described_class.new(nil)
      end.to raise_error(ArgumentError, "fonts cannot be nil or empty")
    end

    it "raises error when fonts is empty" do
      expect do
        described_class.new([])
      end.to raise_error(ArgumentError, "fonts cannot be nil or empty")
    end

    it "raises error when fonts is not an array" do
      expect do
        described_class.new("not_array")
      end.to raise_error(ArgumentError, "fonts must be an array")
    end

    it "raises error when fonts don't respond to table_data" do
      bad_fonts = [Object.new, Object.new]
      expect do
        described_class.new(bad_fonts)
      end.to raise_error(ArgumentError, /must respond to table_data/)
    end
  end

  describe "#build" do
    let(:builder) { described_class.new(fonts) }
    let(:mock_analyzer) { instance_double(Fontisan::Collection::TableAnalyzer) }
    let(:mock_deduplicator) { instance_double(Fontisan::Collection::TableDeduplicator) }
    let(:mock_calculator) { instance_double(Fontisan::Collection::OffsetCalculator) }
    let(:mock_writer) { instance_double(Fontisan::Collection::Writer) }

    let(:analysis_report) do
      {
        total_fonts: 2,
        table_checksums: {},
        shared_tables: {},
        unique_tables: {},
        space_savings: 100,
        sharing_percentage: 33.3,
      }
    end

    let(:sharing_map) { { 0 => {}, 1 => {} } }
    let(:statistics) { { total_tables: 6, shared_tables: 2 } }
    let(:offsets) { { header_offset: 0, table_offsets: {} } }
    let(:binary) { "BINARY_DATA" }

    before do
      allow(Fontisan::Collection::TableAnalyzer).to receive(:new).and_return(mock_analyzer)
      allow(mock_analyzer).to receive(:analyze).and_return(analysis_report)

      allow(Fontisan::Collection::TableDeduplicator).to receive(:new).and_return(mock_deduplicator)
      allow(mock_deduplicator).to receive_messages(
        build_sharing_map: sharing_map, statistics: statistics,
      )

      allow(Fontisan::Collection::OffsetCalculator).to receive(:new).and_return(mock_calculator)
      allow(mock_calculator).to receive(:calculate).and_return(offsets)

      allow(Fontisan::Collection::Writer).to receive(:new).and_return(mock_writer)
      allow(mock_writer).to receive(:write_collection).and_return(binary)
    end

    it "returns build result" do
      result = builder.build

      expect(result).to be_a(Hash)
      expect(result).to have_key(:binary)
      expect(result).to have_key(:space_savings)
      expect(result).to have_key(:analysis)
      expect(result).to have_key(:statistics)
      expect(result).to have_key(:format)
      expect(result).to have_key(:num_fonts)
    end

    it "includes binary data" do
      result = builder.build
      expect(result[:binary]).to eq(binary)
    end

    it "includes space savings" do
      result = builder.build
      expect(result[:space_savings]).to eq(100)
    end

    it "includes format" do
      result = builder.build
      expect(result[:format]).to eq(:ttc)
    end

    it "includes number of fonts" do
      result = builder.build
      expect(result[:num_fonts]).to eq(2)
    end

    it "caches result in instance variable" do
      result1 = builder.build
      result2 = builder.result
      expect(result2).to eq(result1)
    end
  end

  describe "#build_to_file" do
    let(:builder) { described_class.new(fonts) }
    let(:temp_file) { Tempfile.new(["test", ".ttc"]) }
    let(:binary) { "TEST_BINARY" }

    before do
      allow(builder).to receive(:build).and_return({
                                                     binary: binary,
                                                     space_savings: 100,
                                                     num_fonts: 2,
                                                     format: :ttc,
                                                     analysis: {},
                                                     statistics: {},
                                                   })
    end

    after do
      temp_file.close
      temp_file.unlink
    end

    it "writes binary to file" do
      builder.build_to_file(temp_file.path)
      expect(File.exist?(temp_file.path)).to be true
    end

    it "includes output path in result" do
      result = builder.build_to_file(temp_file.path)
      expect(result[:output_path]).to eq(temp_file.path)
    end

    it "includes output size in result" do
      result = builder.build_to_file(temp_file.path)
      expect(result[:output_size]).to eq(binary.bytesize)
    end
  end

  describe "#analyze" do
    let(:builder) { described_class.new(fonts) }
    let(:mock_analyzer) { instance_double(Fontisan::Collection::TableAnalyzer) }
    let(:analysis_report) { { total_fonts: 2, space_savings: 100 } }

    before do
      allow(Fontisan::Collection::TableAnalyzer).to receive(:new).and_return(mock_analyzer)
      allow(mock_analyzer).to receive(:analyze).and_return(analysis_report)
    end

    it "returns analysis report" do
      result = builder.analyze
      expect(result).to eq(analysis_report)
    end

    it "does not build collection" do
      expect(builder).not_to receive(:build)
      builder.analyze
    end
  end

  describe "#potential_savings" do
    let(:builder) { described_class.new(fonts) }

    before do
      allow(builder).to receive(:analyze).and_return({ space_savings: 150 })
    end

    it "returns space savings from analysis" do
      savings = builder.potential_savings
      expect(savings).to eq(150)
    end
  end

  describe "#validate!" do
    it "passes validation for valid fonts" do
      builder = described_class.new(fonts)
      expect { builder.validate! }.not_to raise_error
    end

    it "raises error for single font" do
      builder = described_class.new([font1])
      expect do
        builder.validate!
      end.to raise_error(Fontisan::Error, /requires at least 2 fonts/)
    end
  end

  describe "format validation" do
    it "accepts :ttc format" do
      expect do
        described_class.new(fonts, format: :ttc)
      end.not_to raise_error
    end

    it "accepts :otc format" do
      expect do
        described_class.new(fonts, format: :otc)
      end.not_to raise_error
    end

    it "raises error for invalid format" do
      expect do
        described_class.new(fonts, format: :invalid)
      end.to raise_error(ArgumentError, /Invalid format/)
    end
  end

  describe "accessor methods" do
    let(:builder) { described_class.new(fonts, format: :otc, optimize: false) }

    it "allows reading format" do
      expect(builder.format).to eq(:otc)
    end

    it "allows modifying format" do
      builder.format = :ttc
      expect(builder.format).to eq(:ttc)
    end

    it "allows reading optimize" do
      expect(builder.optimize).to be false
    end

    it "allows modifying optimize" do
      builder.optimize = true
      expect(builder.optimize).to be true
    end
  end
end
