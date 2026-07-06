# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Woff2::LocaFormat do
  describe "::SHORT" do
    subject(:format) { described_class::SHORT }

    it "has code 0 (matches head.indexToLocFormat for short)" do
      expect(format.code).to eq(0)
    end

    it "requires 2-byte alignment between glyphs" do
      expect(format.alignment).to eq(2)
    end

    it "uses 2-byte loca entries" do
      expect(format.entry_width).to eq(2)
    end

    it { is_expected.to be_short }
    it { is_expected.not_to be_long }
  end

  describe "::LONG" do
    subject(:format) { described_class::LONG }

    it "has code 1 (matches head.indexToLocFormat for long)" do
      expect(format.code).to eq(1)
    end

    it "has no alignment requirement (alignment = 1)" do
      expect(format.alignment).to eq(1)
    end

    it "uses 4-byte loca entries" do
      expect(format.entry_width).to eq(4)
    end

    it { is_expected.to be_long }
    it { is_expected.not_to be_short }
  end

  describe "::choose_for" do
    it "picks SHORT when glyf fits in uint16 range" do
      expect(described_class.choose_for(glyf_bytesize: 100)).to eq(described_class::SHORT)
      at_boundary = described_class.choose_for(glyf_bytesize: described_class::SHORT_GLYF_MAX)
      expect(at_boundary).to eq(described_class::SHORT)
    end

    it "picks LONG when glyf exceeds short loca range" do
      over_boundary = described_class.choose_for(glyf_bytesize: described_class::SHORT_GLYF_MAX + 1)
      expect(over_boundary).to eq(described_class::LONG)
      expect(described_class.choose_for(glyf_bytesize: 1_000_000)).to eq(described_class::LONG)
    end

    it "treats SHORT_GLYF_MAX as the boundary" do
      # 131070 = 65535 * 2 — the highest offset addressable by short loca
      expect(described_class::SHORT_GLYF_MAX).to eq(131070)
    end
  end

  describe "#loca_size" do
    it "computes (num_glyphs + 1) × entry_width" do
      expect(described_class::SHORT.loca_size(80)).to eq(162)   # 81 × 2
      expect(described_class::LONG.loca_size(80)).to eq(324)    # 81 × 4
      expect(described_class::LONG.loca_size(4940)).to eq(19_764)
    end

    it "is zero for the degenerate 0-glyph case (only the sentinel)" do
      expect(described_class::SHORT.loca_size(0)).to eq(2)
    end
  end

  describe "#padding_after" do
    context "with SHORT format" do
      let(:format) { described_class::SHORT }

      it "returns 0 when already 2-byte aligned" do
        expect(format.padding_after(0)).to eq(0)
        expect(format.padding_after(100)).to eq(0)
        expect(format.padding_after(2_048)).to eq(0)
      end

      it "returns 1 when one byte short of alignment" do
        expect(format.padding_after(101)).to eq(1)
        expect(format.padding_after(2_049)).to eq(1)
      end
    end

    context "with LONG format" do
      let(:format) { described_class::LONG }

      it "always returns 0 (no alignment requirement)" do
        expect(format.padding_after(0)).to eq(0)
        expect(format.padding_after(1)).to eq(0)
        expect(format.padding_after(2)).to eq(0)
        expect(format.padding_after(3)).to eq(0)
        expect(format.padding_after(100_003)).to eq(0)
      end
    end
  end

  describe "round-trip integration with GlyfLocaReconstruct" do
    let(:input_ttf) { fixture_path("fonttools/TestTTF.ttf") }
    let(:font) { Fontisan::FontLoader.load(input_ttf) }
    let(:glyf) { font.table_data["glyf"] }
    let(:loca) { font.table_data["loca"] }
    let(:num_glyphs) { font.table("maxp").num_glyphs }

    it "reconstructs to consistent sizes regardless of chosen format" do
      # Encode the same font with both SHORT and LONG. Each must produce
      # a self-consistent glyf+loca pair where loca addresses every glyph.
      [described_class::SHORT, described_class::LONG].each do |target_format|
        transformed = Fontisan::Woff2::GlyfLocaTransform.new(
          glyf_data: glyf, loca_data: loca, num_glyphs:,
          source_index_format: font.table("head").index_to_loc_format,
          target_format:
        ).transform

        result = Fontisan::Woff2::GlyfLocaReconstruct.new(
          transformed_glyf: transformed,
          num_glyphs:,
          loca_format: target_format,
        ).reconstruct

        # Reconstructed loca must be exactly the size LocaFormat predicts.
        expect(result[:loca].bytesize).to eq(target_format.loca_size(num_glyphs))
        # glyf must be a multiple of the format's alignment.
        if target_format.alignment > 1
          expect(result[:glyf].bytesize % target_format.alignment).to eq(0),
                                                                      "glyf size must be #{target_format.alignment}-byte aligned under " \
                                                                      "#{target_format.short? ? 'SHORT' : 'LONG'} loca"
        end
      end
    end
  end
end
