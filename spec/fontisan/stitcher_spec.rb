# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"

RSpec.describe Fontisan::Stitcher do
  let(:ufo_path) { "/Users/mulgogi/src/external/unicode/last-resort-font/font.ufo" }
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  before { skip "last-resort-font not available" unless Dir.exist?(ufo_path) }

  describe "single-source stitching" do
    it "stitches ASCII letters from one UFO into a TTF" do
      source = Fontisan::Ufo::Font.open(ufo_path)
      stitcher = described_class.new
      stitcher.add_source(:src, source)
      stitcher.include_notdef(from: :src, into: :main)

      # last-resort-font doesn't have ASCII glyphs per se (it has
      # block-representative glyphs). Stitch whatever the first
      # few glyphs are to prove the pipeline.
      stitcher.include_gid(1, from: :src, into: :main)
      stitcher.include_gid(2, from: :src, into: :main)

      out = File.join(tmpdir, "stitched.ttf")
      stitcher.write_to(out, format: :ttf, subfont: :main)
      expect(File.exist?(out)).to be(true)
      expect(File.size(out)).to be > 0

      reopened = Fontisan::FontLoader.load(out)
      expect(reopened.table("maxp").num_glyphs).to be >= 3
    end
  end

  describe "selector registry" do
    it "resolves :range, :codepoints, :gid" do
      expect(Fontisan::Stitcher::Selector.resolve(:range)).to be(Fontisan::Stitcher::Selector::Range)
      expect(Fontisan::Stitcher::Selector.resolve(:codepoints)).to be(Fontisan::Stitcher::Selector::Codepoints)
      expect(Fontisan::Stitcher::Selector.resolve(:gid)).to be(Fontisan::Stitcher::Selector::Gid)
    end

    it "raises on unknown selector" do
      expect { Fontisan::Stitcher::Selector.resolve(:nope) }
        .to raise_error(ArgumentError, /unknown selector/)
    end
  end

  describe "#add_source" do
    it "rejects lookups for unregistered sources" do
      stitcher = described_class.new
      expect { stitcher.include_range(0x41..0x42, from: :ghost, into: :main) }
        .to raise_error(ArgumentError, /unknown source/)
    end
  end
end
