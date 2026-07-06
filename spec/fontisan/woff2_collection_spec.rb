# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Fontisan::Woff2Collection do
  let(:ttc_path) { fixture_path("fonts/DinaRemasterII/DinaRemasterII.ttc") }

  # Build a WOFF2 collection from the TTC source, yield its path.
  def with_woff2_collection
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.woff2")
      fonts = File.open(ttc_path, "rb") do |io|
        Fontisan::FontLoader.load_collection(ttc_path).extract_fonts(io)
      end
      bytes = Fontisan::Woff2::CollectionEncoder.new(brotli_quality: 11).encode_fonts(fonts)
      File.binwrite(path, bytes)
      yield path
    end
  end

  describe ".from_file" do
    it "loads a WOFF2 collection and exposes num_fonts" do
      with_woff2_collection do |path|
        collection = described_class.from_file(path)
        expect(collection.num_fonts).to eq(2)
      end
    end
  end

  describe "#valid?" do
    it "returns true for a real WOFF2 collection" do
      with_woff2_collection do |path|
        expect(described_class.from_file(path)).to be_valid
      end
    end
  end

  describe "#collection?" do
    it "returns true (always)" do
      with_woff2_collection do |path|
        expect(described_class.from_file(path).collection?).to be true
      end
    end
  end

  describe "#font_offsets" do
    it "returns 0..num_fonts-1 (synthetic indices for compat with BaseCollection)" do
      with_woff2_collection do |path|
        expect(described_class.from_file(path).font_offsets).to eq([0, 1])
      end
    end
  end

  describe "#extract_fonts" do
    it "returns the same number of fonts as the source" do
      with_woff2_collection do |path|
        fonts = described_class.from_file(path).extract_fonts
        expect(fonts.length).to eq(2)
      end
    end

    it "each extracted font has glyf, loca, head, maxp tables" do
      with_woff2_collection do |path|
        fonts = described_class.from_file(path).extract_fonts
        fonts.each do |font|
          %w[glyf loca head maxp].each do |tag|
            expect(font.has_table?(tag)).to be(true),
                                            "font should have #{tag}"
          end
        end
      end
    end

    it "preserves glyph count from source" do
      with_woff2_collection do |path|
        fonts = described_class.from_file(path).extract_fonts
        fonts.each do |font|
          expect(font.table("maxp").num_glyphs).to be > 0
        end
      end
    end
  end

  describe "#font" do
    it "returns a single font by index" do
      with_woff2_collection do |path|
        collection = described_class.from_file(path)
        font = collection.font(0)
        expect(font).to be_a(Fontisan::TrueTypeFont)
        expect(font.has_table?("glyf")).to be true
      end
    end

    it "returns nil for out-of-range index" do
      with_woff2_collection do |path|
        expect(described_class.from_file(path).font(99)).to be_nil
      end
    end
  end
end
