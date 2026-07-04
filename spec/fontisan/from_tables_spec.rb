# frozen_string_literal: true

require "spec_helper"
require "fontisan"
require "tmpdir"

# Reproduces issue #79: TrueTypeFont.from_tables / OpenTypeFont.from_tables
# left parsed_tables empty because BinData-derived tag strings are
# ASCII-8BIT and the lookup literal is UTF-8 — String#eql? is encoding-
# sensitive so Hash lookup returned nil. Fixed by normalizing keys in
# SfntFont#table_data= and normalizing the tag at entry to #table.
RSpec.describe "Fontisan from_tables round-trip (issue #79)" do
  shared_examples "from_tables parses tables on lookup" do
    let(:source_path) { source_fixture_path }
    let(:source) { Fontisan::FontLoader.load(source_path) }

    let(:tables) do
      source.table_names.each_with_object({}) do |tag, h|
        raw = begin
          source.table(tag)&.raw_data
        rescue StandardError
          nil
        end
        h[tag] = raw if raw && !raw.empty?
      end
    end

    let(:rebuilt) { font_class.from_tables(tables) }

    it "exposes has_table?(tag) for every key in the input hash" do
      tables.each_key do |tag|
        expect(rebuilt.has_table?(tag)).to be(true)
      end
    end

    it "returns a parsed instance from table(tag), not nil" do
      expect(rebuilt.table("head")).to be_a(Fontisan::Tables::Head)
      expect(rebuilt.table("maxp")).to be_a(Fontisan::Tables::Maxp)
    end

    it "round-trips: table bytes extracted from the rebuilt font match the input" do
      # Normalize input keys to UTF-8 so Hash#eq (which is encoding-
      # sensitive via eql?) matches the normalized rebuilt.table_data.
      input_normalized = tables.transform_keys { |k| k.dup.force_encoding("UTF-8") }
      expect(rebuilt.table_data).to eq(input_normalized)
    end

    describe "tag encoding robustness" do
      it "looks up tables when the caller passes a UTF-8 literal" do
        expect(rebuilt.table("head".dup.force_encoding("UTF-8")))
          .to be_a(Fontisan::Tables::Head)
      end

      it "looks up tables when the caller passes an ASCII-8BIT binary string" do
        expect(rebuilt.table("head".b)).to be_a(Fontisan::Tables::Head)
      end

      it "looks up tables when the caller passes a frozen string" do
        expect(rebuilt.table("head")).to be_a(Fontisan::Tables::Head)
      end

      it "caches parsed instances under the normalized key (no double-parse)" do
        # Same tag, different encodings — must hit the cache, not re-parse.
        rebuilt.table("head")
        before = rebuilt.parsed_tables.size
        rebuilt.table("head".b)
        rebuilt.table("head")
        expect(rebuilt.parsed_tables.size).to eq(before)
      end
    end

    it "writes WOFF2 via OutputWriter from the rebuilt tables" do
      Dir.mktmpdir do |dir|
        out_path = File.join(dir, "out.woff2")
        Fontisan::Pipeline::OutputWriter.new(out_path, :woff2).write(tables)
        expect(File.exist?(out_path)).to be(true)
        expect(File.size(out_path)).to be > 0
      end
    end
  end

  describe Fontisan::TrueTypeFont do
    it_behaves_like "from_tables parses tables on lookup" do
      let(:font_class) { described_class }
      let(:source_fixture_path) { "spec/fixtures/fonttools/TestTTF.ttf" }
    end
  end

  describe Fontisan::OpenTypeFont do
    it_behaves_like "from_tables parses tables on lookup" do
      let(:font_class) { described_class }
      let(:source_fixture_path) { "spec/fixtures/fonttools/TestOTF.otf" }
    end
  end

  # Direct unit test for the encoding-normalization fix on the setter,
  # independent of from_tables end-to-end behavior.
  describe Fontisan::SfntFont, "#table_data= normalizes key encoding" do
    let(:font) do
      # Build a bare-ish SfntFont by loading any fixture; we only care
      # about the table_data hash on the resulting instance.
      Fontisan::FontLoader.load("spec/fixtures/fonttools/TestTTF.ttf")
    end

    it "converts ASCII-8BIT keys to UTF-8" do
      font.table_data = { "head".b => "bytes" }
      expect(font.table_data.keys.first.encoding).to eq(Encoding::UTF_8)
    end

    it "leaves UTF-8 keys as UTF-8" do
      font.table_data = { "head" => "bytes" }
      expect(font.table_data.keys.first.encoding).to eq(Encoding::UTF_8)
    end

    it "preserves key equality post-normalization" do
      font.table_data = { "head".b => "bytes" }
      expect(font.table_data.key?("head")).to be(true)
      expect(font.table_data["head"]).to eq("bytes")
    end
  end
end
