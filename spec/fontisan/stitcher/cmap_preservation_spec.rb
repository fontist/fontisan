# frozen_string_literal: true

require "spec_helper"
require "fontisan"
require "fontisan/stitcher"

# Regression tests for BUG-stitcher-drops-plane1-codepoints.md
#
# The bug claimed that Plane 1 codepoints (U+10000..U+1FFFF) and the
# topmost consecutive gid range of certain donors were silently
# dropped by the Stitcher. These specs verify the current
# implementation preserves all cmap entries.
RSpec.describe "Stitcher cmap preservation (regression)", :donors do
  # Skip if required donor files aren't present
  before do
    skip "donor files not available" unless File.exist?(
      "/Users/mulgogi/src/essenfont/essenfont/references/input-fonts/Lentariso-Regular.ttf"
    )
  end

  let(:lentariso_path) { "/Users/mulgogi/src/essenfont/essenfont/references/input-fonts/Lentariso-Regular.ttf" }

  it "preserves all Plane 1 codepoints from Lentariso" do
    src = Fontisan::FontLoader.load(lentariso_path)
    src_cmap = src.table("cmap").unicode_mappings
    plane1 = src_cmap.keys.select { |cp| cp >= 0x10000 && cp <= 0x1FFFF }

    stitcher = Fontisan::Stitcher.new
    stitcher.add_source(:lentariso, src)
    stitcher.include_notdef(from: :lentariso)
    stitcher.include_codepoints(plane1, from: :lentariso)

    Dir.mktmpdir do |dir|
      out_path = File.join(dir, "out.ttf")
      stitcher.write_to(out_path, format: :ttf)

      out = Fontisan::FontLoader.load(out_path)
      out_cmap = out.table("cmap").unicode_mappings
      out_plane1 = out_cmap.keys.select { |cp| cp >= 0x10000 && cp <= 0x1FFFF }

      expect(out_plane1.size).to eq(plane1.size),
        "expected #{plane1.size} Plane 1 codepoints, got #{out_plane1.size}"
    end
  end

  it "preserves the topmost consecutive gid range of Kedebideri" do
    kedebideri_path = "/Users/mulgogi/src/essenfont/essenfont/references/input-fonts/Kedebideri-Regular.ttf"
    skip "Kedebideri not present" unless File.exist?(kedebideri_path)

    src = Fontisan::FontLoader.load(kedebideri_path)
    src_cmap = src.table("cmap").unicode_mappings
    beria_erfe = src_cmap.keys.select { |cp| cp >= 0x16EA0 && cp <= 0x16EDF }

    stitcher = Fontisan::Stitcher.new
    stitcher.add_source(:kedebideri, src)
    stitcher.include_notdef(from: :kedebideri)
    stitcher.include_codepoints(beria_erfe, from: :kedebideri)

    Dir.mktmpdir do |dir|
      out_path = File.join(dir, "out.ttf")
      stitcher.write_to(out_path, format: :ttf)

      out = Fontisan::FontLoader.load(out_path)
      out_cmap = out.table("cmap").unicode_mappings
      out_beria = out_cmap.keys.select { |cp| cp >= 0x16EA0 && cp <= 0x16EDF }

      expect(out_beria.size).to eq(beria_erfe.size),
        "expected #{beria_erfe.size} Beria Erfe cps, got #{out_beria.size}; " \
        "dropped: #{(beria_erfe - out_beria).map { |cp| format('U+%04X', cp) }.join(', ')}"
    end
  end
end
