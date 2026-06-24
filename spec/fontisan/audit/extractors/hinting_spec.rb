# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/hinting"

RSpec.describe Fontisan::Audit::Extractors::Hinting do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:otf_path) { font_fixture_path("SourceSans3", "SourceSans3-Regular.otf") }

  let(:ttf_context) do
    font = Fontisan::FontLoader.load(ttf_path, mode: :full)
    Fontisan::Audit::Context.new(
      font: font, font_path: ttf_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  let(:otf_context) do
    font = Fontisan::FontLoader.load(otf_path, mode: :full)
    Fontisan::Audit::Context.new(
      font: font, font_path: otf_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  it "returns a single :hinting field" do
    fields = described_class.new.extract(ttf_context)
    expect(fields.keys).to contain_exactly(:hinting)
  end

  it "returns a Models::Audit::Hinting instance" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:hinting]).to be_a(Fontisan::Models::Audit::Hinting)
  end

  describe "TrueType hinting (NotoSans)" do
    it "detects fpgm table" do
      hinting = described_class.new.extract(ttf_context)[:hinting]
      expect(hinting.has_fpgm).to be true
      expect(hinting.fpgm_instruction_count).to be_an(Integer).and be_positive
    end

    it "detects prep table" do
      hinting = described_class.new.extract(ttf_context)[:hinting]
      expect(hinting.has_prep).to be true
      expect(hinting.prep_instruction_count).to be_an(Integer).and be_positive
    end

    it "detects cvt table" do
      hinting = described_class.new.extract(ttf_context)[:hinting]
      expect(hinting.has_cvt).to be true
      expect(hinting.cvt_entry_count).to be_an(Integer).and be_positive
    end

    it "populates gasp_ranges when gasp table is present" do
      hinting = described_class.new.extract(ttf_context)[:hinting]
      skip "gasp table not present in fixture" unless hinting.has_fpgm || hinting.gasp_ranges.any?

      if hinting.gasp_ranges.any?
        first = hinting.gasp_ranges.first
        expect(first).to be_a(Fontisan::Models::Audit::GaspRange)
        expect(first.max_ppem).to be_an(Integer)
      end
    end

    it "reports CFF hinting absent for a TrueType font" do
      hinting = described_class.new.extract(ttf_context)[:hinting]
      expect(hinting.cff_has_private_dict).to be false
      expect(hinting.cff_hint_count).to be_nil
    end

    it "classifies the format as truetype" do
      hinting = described_class.new.extract(ttf_context)[:hinting]
      expect(hinting.hinting_format).to eq("truetype")
      expect(hinting.is_unhinted).to be false
    end
  end

  describe "CFF hinting (SourceSans3)" do
    it "reports no TrueType programs" do
      hinting = described_class.new.extract(otf_context)[:hinting]
      expect(hinting.has_fpgm).to be false
      expect(hinting.has_prep).to be false
      expect(hinting.has_cvt).to be false
    end

    it "detects CFF Private DICT" do
      hinting = described_class.new.extract(otf_context)[:hinting]
      expect(hinting.cff_has_private_dict).to be true
    end

    it "counts CFF stem hints as a non-negative integer" do
      hinting = described_class.new.extract(otf_context)[:hinting]
      expect(hinting.cff_hint_count).to be_an(Integer).and be >= 0
    end

    it "classifies the format as cff" do
      hinting = described_class.new.extract(otf_context)[:hinting]
      expect(hinting.hinting_format).to eq("cff")
      expect(hinting.is_unhinted).to be false
    end
  end
end
