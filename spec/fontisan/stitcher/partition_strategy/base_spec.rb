# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher/partition_strategy"
require "fontisan/stitcher/glyph_limit"

RSpec.describe Fontisan::Stitcher::PartitionStrategy::Base do
  let(:glyph_limit) { Fontisan::Stitcher::GlyphLimit }

  describe "DEFAULT_CAP" do
    it "is derived from GlyphLimit::TTF_GLYPH_CAP minus the reserved slots" do
      expected = glyph_limit::TTF_GLYPH_CAP \
               - described_class::NOTDEF_RESERVED \
               - described_class::COMPOSITE_HEADROOM
      expect(described_class::DEFAULT_CAP).to eq(expected)
    end

    it "leaves enough composite-expansion headroom below the hard cap" do
      # The point of the headroom: a partition full at DEFAULT_CAP codepoints
      # must still fit under the 65,535 hard glyph cap after compile adds
      # .notdef + composites. 5,534 slots ≥ ~5% of a typical BMP partition
      # (≈3,000 composites on a 60,000-cp font). Pinning the value guards
      # against an accidental tightening that would re-introduce PR #78's bug.
      expect(described_class::NOTDEF_RESERVED).to eq(1)
      expect(described_class::COMPOSITE_HEADROOM).to eq(5_534)
      expect(described_class::DEFAULT_CAP).to eq(60_000)
    end

    it "stays below the format's hard glyph cap" do
      expect(described_class::DEFAULT_CAP).to be < glyph_limit::TTF_GLYPH_CAP
    end
  end

  describe ".cap_for" do
    it "returns DEFAULT_CAP for :ttf (the default format)" do
      expect(described_class.cap_for(:ttf)).to eq(described_class::DEFAULT_CAP)
    end

    it "derives the cap from the format's glyph limit" do
      # Today every format caps at 65,535, so cap_for returns the same
      # value for all of them. The formula still has to go through
      # GlyphLimit.for_format so that a future CFF2 bump cascades.
      expect(described_class.cap_for(:otf)).to eq(60_000)
      expect(described_class.cap_for(:otf2)).to eq(60_000)
    end

    it "raises ArgumentError for unknown formats (delegated to GlyphLimit)" do
      expect do
        described_class.cap_for(:woff)
      end.to raise_error(ArgumentError,
                         /unknown format/)
    end
  end

  describe "#call" do
    it "raises NotImplementedError on the abstract base" do
      expect { described_class.new.call({}) }
        .to raise_error(NotImplementedError, /must implement #call/)
    end

    it "defaults the cap to DEFAULT_CAP when not given" do
      # The signature contract: subclasses can rely on cap being set.
      method = described_class.instance_method(:call)
      expect(method.parameters).to include(%i[key cap])
    end
  end
end
