# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"

# Issue #81: Stitcher#add_source(label, font, remap:) gives donors
# whose glyphs live at non-canonical codepoints a first-class API for
# exposing those glyphs at their canonical targets, without callers
# reaching into the donor's cached cmap.
RSpec.describe Fontisan::Stitcher::Source, "#remap" do
  let(:donor) { Fontisan::FontLoader.load("spec/fixtures/fonttools/TestTTF.ttf") }

  # TestTTF has 5 cmap entries: U+0000, U+000D, U+0020 (space),
  # U+002E (period), U+2026 (ellipsis). Of these, gids 1-3 (whitespace
  # / control) have no outlines — extract_truetype_glyph returns nil
  # for them. Gid 4 (period) is the simplest glyph with real outlines,
  # so use it for tests that need to inspect the extracted glyph.
  let(:source_cp) { 0x2E } # period
  let(:source_gid) { donor.table("cmap").unicode_mappings[source_cp] }

  describe "without remap (default)" do
    let(:source) { described_class.new(donor) }

    it "looks up the donor's raw codepoints directly" do
      expect(source.gid_for_codepoint(source_cp)).to eq(source_gid)
    end

    it "exposes every codepoint the donor's cmap has" do
      expect(source.remap).to be_nil
    end

    it "attaches the donor's raw codepoints to extracted glyphs" do
      glyph = source.glyph_for_gid(source_gid)
      expect(glyph.unicodes).to include(source_cp)
    end
  end

  describe "with a remap" do
    # Pretend the donor's space + period glyphs are actually letters
    # of a hypothetical script that lives at U+11DB0.. (essenfont's
    # Tolong Siki range). The remap exposes those glyphs at the new
    # targets while keeping the donor's cmap untouched.
    let(:remap) do
      { source_cp => 0x11DB0 }
    end
    let(:source) { described_class.new(donor, remap: remap) }

    it "exposes the remap hash on the #remap reader" do
      expect(source.remap).to eq(remap)
    end

    it "looks up target codepoints via the remap (translates to source)" do
      expect(source.gid_for_codepoint(0x11DB0)).to eq(source_gid)
    end

    it "returns nil for codepoints the remap does not cover" do
      # Source cps not in the remap are hidden — looking up the raw
      # source cp directly must return nil.
      expect(source.gid_for_codepoint(source_cp)).to be_nil
      # And codepoints the remap doesn't target are nil too.
      expect(source.gid_for_codepoint(0x11DB5)).to be_nil
    end

    it "does not mutate the donor's cmap" do
      original_mappings = donor.table("cmap").unicode_mappings
      original_size = original_mappings.size

      # Force a lookup that runs the remap path.
      source.gid_for_codepoint(0x11DB0)

      expect(donor.table("cmap").unicode_mappings.size).to eq(original_size)
      expect(donor.table("cmap").unicode_mappings[source_cp]).to eq(source_gid)
    end

    it "attaches target codepoints (not source codepoints) to extracted glyphs" do
      glyph = source.glyph_for_gid(source_gid)
      expect(glyph.unicodes).to include(0x11DB0)
      expect(glyph.unicodes).not_to include(source_cp)
    end

    it "accepts string keys and coerces to Integer" do
      # Some manifests (YAML loaders) hand back string keys. Coerce
      # rather than blow up — matches the issue body's proposal.
      source_with_strings = described_class.new(donor, remap: { source_cp.to_s => 0x11DB0.to_s })
      expect { source_with_strings.gid_for_codepoint(0x11DB0) }.not_to raise_error
    end

    it "supports multiple sources with different remaps on one Stitcher" do
      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:remapped, donor, remap: { source_cp => 0x11DB0 })
      stitcher.add_source(:passthrough, donor)

      remapped_gid = stitcher.instance_variable_get(:@sources)[:remapped].gid_for_codepoint(0x11DB0)
      passthrough_gid = stitcher.instance_variable_get(:@sources)[:passthrough].gid_for_codepoint(source_cp)

      expect(remapped_gid).to eq(source_gid)
      expect(passthrough_gid).to eq(source_gid)
    end
  end

  describe "with an empty remap" do
    let(:source) { described_class.new(donor, remap: {}) }

    it "exposes no codepoints (every source cp is dropped by design)" do
      expect(source.gid_for_codepoint(source_cp)).to be_nil
    end

    it "does not attach any codepoints to extracted glyphs" do
      glyph = source.glyph_for_gid(source_gid)
      attached = glyph.unicodes & donor.table("cmap").unicode_mappings.keys
      expect(attached).to be_empty
    end
  end

  describe Fontisan::Stitcher, "#add_source with remap:" do
    it "forwards the remap to the Source it constructs" do
      stitcher = described_class.new
      stitcher.add_source(:tolong_siki, donor, remap: { source_cp => 0x11DB0 })

      source = stitcher.instance_variable_get(:@sources)[:tolong_siki]
      expect(source).to be_a(Fontisan::Stitcher::Source)
      expect(source.remap).to eq(source_cp => 0x11DB0)
    end

    it "defaults remap to nil when omitted (backwards-compatible)" do
      stitcher = described_class.new
      stitcher.add_source(:plain, donor)

      source = stitcher.instance_variable_get(:@sources)[:plain]
      expect(source.remap).to be_nil
    end
  end
end
