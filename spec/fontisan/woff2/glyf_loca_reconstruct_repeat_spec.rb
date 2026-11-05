# frozen_string_literal: true

require "fontisan"
require "tmpdir"
require "open3"

# The TrueType flag REPEAT byte counts the EXTRA repeats (OpenType glyf
# spec), not the run length. fontisan/fontisan#156 convert goldens.
RSpec.describe Fontisan::Woff2::GlyfLocaReconstruct do
  describe "flag run-length encoding" do
    subject(:encoded) do
      described_class.allocate.send(:encode_flags_rle, flags).bytes
    end

    context "with three identical flags" do
      let(:flags) { [0x31, 0x31, 0x31] }

      it "emits the flag with REPEAT set and an extra-repeat count of 2" do
        expect(encoded).to eq([0x31 | 0x08, 2])
      end
    end

    context "with a run of two and a distinct flag" do
      let(:flags) { [0x01, 0x01, 0x23] }

      it "emits a repeat count of 1 then the next flag" do
        expect(encoded).to eq([0x01 | 0x08, 1, 0x23])
      end
    end
  end

  describe "against the pinned woff2_decompress" do
    let(:root) { File.expand_path("../../..", __dir__) }
    let(:decoder) { File.join(root, "corpus", "fonts", ".tools", "woff2", "bin", "woff2_decompress") }
    let(:source) do
      File.join(root, "corpus", "fonts", "source-sans-3-regular-ttf-woff2", "SourceSans3-Regular.ttf.woff2")
    end

    def outlines(font)
      glyf = font.table("glyf")
      loca = font.table("loca")
      loca.parse_with_context(font.table("head").index_to_loc_format, font.table("maxp").num_glyphs)
      Array.new(font.table("maxp").num_glyphs) do |gid|
        g = glyf.glyph_for(gid, loca, font.table("head"))
        if g.nil? then []
        elsif g.respond_to?(:points) then [g.num_contours, g.end_pts_of_contours, g.points]
        else [:composite]
        end
      end
    end

    it "rebuilds the outlines of a real WOFF2 equal to Google's decoder" do
      skip "run rake corpus:fetch and scripts/build-woff2.sh first" unless File.exist?(decoder) && File.exist?(source)

      Dir.mktmpdir do |dir|
        FileUtils.cp(source, File.join(dir, "in.woff2"))
        _out, err, status = Open3.capture3(decoder, File.join(dir, "in.woff2"))
        expect(status).to be_success, err
        want = Fontisan::FontLoader.load(File.join(dir, "in.ttf"), mode: Fontisan::LoadingModes::FULL, lazy: false)
        got = Fontisan::FontLoader.load(source, mode: Fontisan::LoadingModes::FULL, lazy: false)
        expect(outlines(got)).to eq(outlines(want))
      end
    end
  end
end
