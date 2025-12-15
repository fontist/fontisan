# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe Fontisan::LoadingModes do
  describe "module constants" do
    it "defines METADATA mode" do
      expect(described_class::METADATA).to eq(:metadata)
    end

    it "defines FULL mode" do
      expect(described_class::FULL).to eq(:full)
    end
  end

  describe ".all_modes" do
    it "returns all available modes" do
      expect(described_class.all_modes).to contain_exactly(:metadata, :full)
    end
  end

  describe ".valid_mode?" do
    it "returns true for metadata mode" do
      expect(described_class.valid_mode?(:metadata)).to be true
    end

    it "returns true for full mode" do
      expect(described_class.valid_mode?(:full)).to be true
    end

    it "returns false for invalid mode" do
      expect(described_class.valid_mode?(:invalid)).to be false
    end

    it "returns false for nil" do
      expect(described_class.valid_mode?(nil)).to be false
    end
  end

  describe ".tables_for" do
    it "returns metadata tables for metadata mode" do
      tables = described_class.tables_for(:metadata)
      expect(tables).to eq(%w[name head hhea maxp OS/2 post])
    end

    it "returns :all for full mode" do
      tables = described_class.tables_for(:full)
      expect(tables).to eq(:all)
    end

    it "raises error for invalid mode" do
      expect {
        described_class.tables_for(:invalid)
      }.to raise_error(ArgumentError, /Invalid mode/)
    end
  end

  describe ".table_allowed?" do
    context "in metadata mode" do
      it "allows name table" do
        expect(described_class.table_allowed?(:metadata, "name")).to be true
      end

      it "allows head table" do
        expect(described_class.table_allowed?(:metadata, "head")).to be true
      end

      it "allows hhea table" do
        expect(described_class.table_allowed?(:metadata, "hhea")).to be true
      end

      it "allows maxp table" do
        expect(described_class.table_allowed?(:metadata, "maxp")).to be true
      end

      it "allows OS/2 table" do
        expect(described_class.table_allowed?(:metadata, "OS/2")).to be true
      end

      it "allows post table" do
        expect(described_class.table_allowed?(:metadata, "post")).to be true
      end

      it "disallows GSUB table" do
        expect(described_class.table_allowed?(:metadata, "GSUB")).to be false
      end

      it "disallows GPOS table" do
        expect(described_class.table_allowed?(:metadata, "GPOS")).to be false
      end

      it "disallows glyf table" do
        expect(described_class.table_allowed?(:metadata, "glyf")).to be false
      end

      it "disallows cmap table" do
        expect(described_class.table_allowed?(:metadata, "cmap")).to be false
      end

      it "disallows CFF table" do
        expect(described_class.table_allowed?(:metadata, "CFF ")).to be false
      end
    end

    context "in full mode" do
      it "allows name table" do
        expect(described_class.table_allowed?(:full, "name")).to be true
      end

      it "allows GSUB table" do
        expect(described_class.table_allowed?(:full, "GSUB")).to be true
      end

      it "allows GPOS table" do
        expect(described_class.table_allowed?(:full, "GPOS")).to be true
      end

      it "allows glyf table" do
        expect(described_class.table_allowed?(:full, "glyf")).to be true
      end

      it "allows any table" do
        expect(described_class.table_allowed?(:full, "arbitrary")).to be true
      end
    end

    it "raises error for invalid mode" do
      expect {
        described_class.table_allowed?(:invalid, "name")
      }.to raise_error(ArgumentError, /Invalid mode/)
    end
  end

  describe ".default_lazy?" do
    it "returns true for metadata mode" do
      expect(described_class.default_lazy?(:metadata)).to be true
    end

    it "returns true for full mode" do
      expect(described_class.default_lazy?(:full)).to be true
    end

    it "raises error for invalid mode" do
      expect {
        described_class.default_lazy?(:invalid)
      }.to raise_error(ArgumentError, /Invalid mode/)
    end
  end

  describe ".description" do
    it "returns description for metadata mode" do
      desc = described_class.description(:metadata)
      expect(desc).to include("Metadata mode")
      expect(desc).to include("otfinfo")
    end

    it "returns description for full mode" do
      desc = described_class.description(:full)
      expect(desc).to include("Full mode")
      expect(desc).to include("all tables")
    end

    it "raises error for invalid mode" do
      expect {
        described_class.description(:invalid)
      }.to raise_error(ArgumentError, /Invalid mode/)
    end
  end
end

RSpec.describe "Loading Modes Integration" do
  let(:ttf_path) { fixture_path("fonts/NotoSans-Regular.ttf") }
  let(:otf_path) { fixture_path("fonts/MonaSans/MonaSans/otf/MonaSans-Medium.otf") }

  describe "FontLoader" do
    context "with metadata mode" do
      it "loads TTF font in metadata mode" do
        font = Fontisan::FontLoader.load(ttf_path, mode: :metadata)
        expect(font).to be_a(Fontisan::TrueTypeFont)
        expect(font.loading_mode).to eq(:metadata)
      end

      it "loads OTF font in metadata mode" do
        font = Fontisan::FontLoader.load(otf_path, mode: :metadata)
        expect(font).to be_a(Fontisan::OpenTypeFont)
        expect(font.loading_mode).to eq(:metadata)
      end

      it "allows access to metadata tables" do
        font = Fontisan::FontLoader.load(ttf_path, mode: :metadata)
        expect(font.table("name")).not_to be_nil
        expect(font.table("head")).not_to be_nil
      end

      it "provides otfinfo-equivalent data" do
        font = Fontisan::FontLoader.load(ttf_path, mode: :metadata)
        expect(font.family_name).not_to be_nil
        expect(font.units_per_em).not_to be_nil
      end
    end

    context "with full mode" do
      it "loads TTF font in full mode by default" do
        font = Fontisan::FontLoader.load(ttf_path)
        expect(font).to be_a(Fontisan::TrueTypeFont)
        expect(font.loading_mode).to eq(:full)
      end

      it "loads OTF font in full mode by default" do
        font = Fontisan::FontLoader.load(otf_path)
        expect(font).to be_a(Fontisan::OpenTypeFont)
        expect(font.loading_mode).to eq(:full)
      end

      it "allows access to all tables" do
        font = Fontisan::FontLoader.load(ttf_path, mode: :full)
        expect(font.table("name")).not_to be_nil
        expect(font.table("head")).not_to be_nil
      end
    end

    context "with lazy loading" do
      it "supports metadata mode with lazy loading" do
        font = Fontisan::FontLoader.load(ttf_path, mode: :metadata, lazy: true)
        expect(font.loading_mode).to eq(:metadata)
        expect(font.lazy_load_enabled).to be true
      end

      it "supports metadata mode with eager loading" do
        font = Fontisan::FontLoader.load(ttf_path, mode: :metadata, lazy: false)
        expect(font.loading_mode).to eq(:metadata)
        expect(font.lazy_load_enabled).to be false
      end

      it "supports full mode with lazy loading" do
        font = Fontisan::FontLoader.load(ttf_path, mode: :full, lazy: true)
        expect(font.loading_mode).to eq(:full)
        expect(font.lazy_load_enabled).to be true
      end

      it "supports full mode with eager loading" do
        font = Fontisan::FontLoader.load(ttf_path, mode: :full, lazy: false)
        expect(font.loading_mode).to eq(:full)
        expect(font.lazy_load_enabled).to be false
      end
    end

    context "with environment variables" do
      around do |example|
        old_mode = ENV["FONTISAN_MODE"]
        old_lazy = ENV["FONTISAN_LAZY"]
        example.run
        ENV["FONTISAN_MODE"] = old_mode
        ENV["FONTISAN_LAZY"] = old_lazy
      end

      it "respects FONTISAN_MODE environment variable" do
        ENV["FONTISAN_MODE"] = "metadata"
        font = Fontisan::FontLoader.load(ttf_path)
        expect(font.loading_mode).to eq(:metadata)
      end

      it "respects FONTISAN_LAZY environment variable" do
        ENV["FONTISAN_LAZY"] = "false"
        font = Fontisan::FontLoader.load(ttf_path)
        expect(font.lazy_load_enabled).to be false
      end

      it "explicit parameters override environment variables" do
        ENV["FONTISAN_MODE"] = "metadata"
        font = Fontisan::FontLoader.load(ttf_path, mode: :full)
        expect(font.loading_mode).to eq(:full)
      end
    end

    context "with collections" do
      it "works with font_index parameter" do
        expect do
          Fontisan::FontLoader.load(ttf_path, font_index: 0)
        end.not_to raise_error
      end
    end
  end

  describe "TrueTypeFont" do
    context "in metadata mode" do
      let(:font) { Fontisan::TrueTypeFont.from_file(ttf_path, mode: :metadata) }

      it "sets loading_mode correctly" do
        expect(font.loading_mode).to eq(:metadata)
      end

      it "parses name table" do
        name_table = font.table("name")
        expect(name_table).not_to be_nil
        expect(name_table).to be_a(Fontisan::Tables::Name)
      end

      it "allows access to all metadata tables" do
        expect(font.table_available?("name")).to be true
        expect(font.table_available?("head")).to be true
        expect(font.table_available?("hhea")).to be true
        expect(font.table_available?("maxp")).to be true
        expect(font.table_available?("OS/2")).to be true
        expect(font.table_available?("post")).to be true
      end

      it "does not load non-metadata tables" do
        expect(font.table_data).not_to have_key("GSUB")
        expect(font.table_data).not_to have_key("GPOS")
        expect(font.table_data).not_to have_key("cmap")
        expect(font.table_data).not_to have_key("glyf")
        expect(font.table_data).not_to have_key("loca")
      end

      it "extracts all name table fields" do
        expect(font.family_name).to be_a(String)
        expect(font.family_name).not_to be_empty
        expect(font.subfamily_name).to be_a(String)
        expect(font.subfamily_name).not_to be_empty
        expect(font.full_name).to be_a(String)
        expect(font.full_name).not_to be_empty
        expect(font.post_script_name).to be_a(String)
        expect(font.post_script_name).not_to be_empty
      end

      it "extracts optional name table fields" do
        expect(font.preferred_family_name).to be_a(String).or be_nil
        expect(font.preferred_subfamily_name).to be_a(String).or be_nil
      end

      it "provides font metrics" do
        expect(font.units_per_em).to be > 0
      end
    end

    context "in full mode" do
      let(:font) { Fontisan::TrueTypeFont.from_file(ttf_path, mode: :full, lazy: false) }

      it "sets loading_mode correctly" do
        expect(font.loading_mode).to eq(:full)
      end

      it "loads all available tables" do
        expect(font.table_data.keys.size).to be > 6
      end

      it "includes metadata tables" do
        expect(font.table_data).to have_key("name")
        expect(font.table_data).to have_key("head")
      end

      it "reports all tables as available" do
        font.table_names.each do |tag|
          expect(font.table_available?(tag)).to be true
        end
      end
    end
  end

  describe "OpenTypeFont" do
    context "in metadata mode" do
      let(:font) { Fontisan::OpenTypeFont.from_file(otf_path, mode: :metadata) }

      it "sets loading_mode correctly" do
        expect(font.loading_mode).to eq(:metadata)
      end

      it "parses name table" do
        name_table = font.table("name")
        expect(name_table).not_to be_nil
        expect(name_table).to be_a(Fontisan::Tables::Name)
      end

      it "allows access to all metadata tables" do
        expect(font.table_available?("name")).to be true
        expect(font.table_available?("head")).to be true
      end

      it "does not load non-metadata tables" do
        expect(font.table_data).not_to have_key("GSUB")
        expect(font.table_data).not_to have_key("GPOS")
        expect(font.table_data).not_to have_key("CFF ")
      end

      it "extracts all name table fields" do
        expect(font.family_name).to be_a(String)
        expect(font.family_name).not_to be_empty
        expect(font.subfamily_name).to be_a(String)
        expect(font.subfamily_name).not_to be_empty
        expect(font.post_script_name).to be_a(String)
        expect(font.post_script_name).not_to be_empty
      end

      it "provides font metrics" do
        expect(font.units_per_em).to be > 0
      end
    end

    context "in full mode" do
      let(:font) { Fontisan::OpenTypeFont.from_file(otf_path, mode: :full, lazy: false) }

      it "sets loading_mode correctly" do
        expect(font.loading_mode).to eq(:full)
      end

      it "loads all available tables" do
        expect(font.table_data.keys.size).to be > 6
      end

      it "includes CFF table for OpenType fonts" do
        expect(font.table_data).to have_key("CFF ")
      end

      it "reports all tables as available" do
        font.table_names.each do |tag|
          expect(font.table_available?(tag)).to be true
        end
      end
    end
  end

  describe "table access control" do
    context "in metadata mode" do
      let(:font) { Fontisan::TrueTypeFont.from_file(ttf_path, mode: :metadata) }

      it "table_available? returns false for non-metadata tables" do
        expect(font.table_available?("cmap")).to be false
        expect(font.table_available?("glyf")).to be false
        expect(font.table_available?("GSUB")).to be false
      end

      it "table() returns nil for non-existent tables" do
        expect(font.table("nonexistent")).to be_nil
      end
    end

    context "in full mode" do
      let(:font) { Fontisan::TrueTypeFont.from_file(ttf_path, mode: :full) }

      it "table_available? returns true for all existing tables" do
        font.table_names.each do |tag|
          expect(font.table_available?(tag)).to be true
        end
      end
    end
  end

  describe "convenience methods" do
    let(:ttf_font) { Fontisan::TrueTypeFont.from_file(ttf_path, mode: :metadata) }
    let(:otf_font) { Fontisan::OpenTypeFont.from_file(otf_path, mode: :metadata) }

    context "on TrueTypeFont" do
      it "provides family_name" do
        expect(ttf_font).to respond_to(:family_name)
        expect(ttf_font.family_name).to be_a(String)
        expect(ttf_font.family_name).not_to be_empty
      end

      it "provides subfamily_name" do
        expect(ttf_font).to respond_to(:subfamily_name)
        expect(ttf_font.subfamily_name).to be_a(String)
        expect(ttf_font.subfamily_name).not_to be_empty
      end

      it "provides full_name" do
        expect(ttf_font).to respond_to(:full_name)
        expect(ttf_font.full_name).to be_a(String)
        expect(ttf_font.full_name).not_to be_empty
      end

      it "provides post_script_name" do
        expect(ttf_font).to respond_to(:post_script_name)
        expect(ttf_font.post_script_name).to be_a(String)
        expect(ttf_font.post_script_name).not_to be_empty
      end
    end

    context "on OpenTypeFont" do
      it "provides family_name" do
        expect(otf_font).to respond_to(:family_name)
        expect(otf_font.family_name).to be_a(String)
        expect(otf_font.family_name).not_to be_empty
      end

      it "provides subfamily_name" do
        expect(otf_font).to respond_to(:subfamily_name)
        expect(otf_font.subfamily_name).to be_a(String)
        expect(otf_font.subfamily_name).not_to be_empty
      end

      it "provides post_script_name" do
        expect(otf_font).to respond_to(:post_script_name)
        expect(otf_font.post_script_name).to be_a(String)
        expect(otf_font.post_script_name).not_to be_empty
      end
    end
  end

  describe "performance and efficiency" do
    let(:test_fonts) { Dir.glob(fixture_path("fonts/**/*.{ttf,otf}")).first(5) }

    it "metadata mode is faster than full mode", :slow do
      skip "No test fonts available" if test_fonts.empty?

      metadata_time = Benchmark.realtime do
        test_fonts.each { |path| Fontisan::FontLoader.load(path, mode: :metadata, lazy: false) }
      end

      full_time = Benchmark.realtime do
        test_fonts.each { |path| Fontisan::FontLoader.load(path, mode: :full, lazy: false) }
      end

      puts "\nPerformance (#{test_fonts.size} fonts):"
      puts "  Metadata: #{(metadata_time * 1000).round(2)}ms"
      puts "  Full:     #{(full_time * 1000).round(2)}ms"
      puts "  Speedup:  #{(full_time / metadata_time).round(1)}x"

      expect(metadata_time).to be < full_time
    end

    it "uses less memory in metadata mode" do
      skip "No test fonts available" unless File.exist?(ttf_path)

      metadata_font = Fontisan::TrueTypeFont.from_file(ttf_path, mode: :metadata, lazy: false)
      full_font = Fontisan::TrueTypeFont.from_file(ttf_path, mode: :full, lazy: false)

      metadata_size = metadata_font.table_data.values.sum(&:bytesize)
      full_size = full_font.table_data.values.sum(&:bytesize)

      puts "\nMemory usage:"
      puts "  Metadata: #{metadata_size} bytes (#{metadata_font.table_data.keys.size} tables)"
      puts "  Full:     #{full_size} bytes (#{full_font.table_data.keys.size} tables)"
      puts "  Saved:    #{((1 - metadata_size.to_f / full_size) * 100).round(1)}%"

      expect(metadata_size).to be < (full_size * 0.5)
    end

    it "provides consistent data extraction across modes" do
      skip "No test fonts available" if test_fonts.empty?

      test_fonts.each do |path|
        metadata_font = Fontisan::FontLoader.load(path, mode: :metadata)
        full_font = Fontisan::FontLoader.load(path, mode: :full)

        expect(metadata_font.family_name).to eq(full_font.family_name)
        expect(metadata_font.subfamily_name).to eq(full_font.subfamily_name)
        expect(metadata_font.post_script_name).to eq(full_font.post_script_name)
      end
    end
  end

  describe "use cases" do
    it "supports font indexing workflow" do
      skip "No test fonts available" unless File.exist?(ttf_path)

      fonts_metadata = []

      time = Benchmark.realtime do
        Dir.glob(fixture_path("fonts/**/*.{ttf,otf}")).first(10).each do |path|
          font = Fontisan::FontLoader.load(path, mode: :metadata)

          fonts_metadata << {
            path: path,
            family: font.family_name,
            subfamily: font.subfamily_name,
            postscript_name: font.post_script_name,
          }
        end
      end

      expect(fonts_metadata).not_to be_empty
      fonts_metadata.each do |metadata|
        expect(metadata[:family]).to be_a(String)
        expect(metadata[:subfamily]).to be_a(String)
        expect(metadata[:postscript_name]).to be_a(String)
      end

      puts "\nIndexed #{fonts_metadata.size} fonts in #{(time * 1000).round(1)}ms"
    end
  end

  describe "error handling" do
    it "rejects invalid mode in FontLoader" do
      expect {
        Fontisan::FontLoader.load(ttf_path, mode: :invalid)
      }.to raise_error(ArgumentError, /Invalid mode/)
    end

    it "rejects invalid mode in TrueTypeFont" do
      expect {
        Fontisan::TrueTypeFont.from_file(ttf_path, mode: :invalid)
      }.to raise_error(ArgumentError, /Invalid mode/)
    end

    it "rejects invalid mode in OpenTypeFont" do
      expect {
        Fontisan::OpenTypeFont.from_file(otf_path, mode: :invalid)
      }.to raise_error(ArgumentError, /Invalid mode/)
    end

    it "handles missing font files" do
      expect {
        Fontisan::FontLoader.load("/nonexistent/font.ttf", mode: :metadata)
      }.to raise_error(Errno::ENOENT)
    end

    it "handles invalid font format" do
      temp_file = Tempfile.new(["invalid", ".ttf"])
      temp_file.write("invalid font data")
      temp_file.close

      expect {
        Fontisan::FontLoader.load(temp_file.path, mode: :metadata)
      }.to raise_error(Fontisan::InvalidFontError)

      temp_file.unlink
    end
  end
end