# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/opentype_layout"
require "fontisan/audit/context"

RSpec.describe Fontisan::Audit::Extractors::OpenTypeLayout do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }

  let(:ttf_context) do
    font = Fontisan::FontLoader.load(ttf_path, mode: :full)
    Fontisan::Audit::Context.new(
      font: font, font_path: ttf_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  it "returns opentype_layout key only" do
    fields = described_class.new.extract(ttf_context)
    expect(fields.keys).to contain_exactly(:opentype_layout)
  end

  context "with an SFNT font that has GSUB and GPOS" do
    let(:fields) { described_class.new.extract(ttf_context) }
    let(:layout) { fields[:opentype_layout] }

    it "returns an OpenTypeLayout model" do
      expect(layout).to be_a(Fontisan::Models::Audit::OpenTypeLayout)
    end

    it "exposes scripts as a sorted unique array" do
      expect(layout.scripts).to be_an(Array)
      expect(layout.scripts).not_to be_empty
      expect(layout.scripts).to eq(layout.scripts.uniq.sort)
    end

    it "exposes features as a sorted unique array" do
      expect(layout.features).to be_an(Array)
      expect(layout.features).to eq(layout.features.uniq.sort)
    end

    it "exposes a per-script breakdown" do
      expect(layout.by_script).to be_an(Array)
      expect(layout.by_script.length).to eq(layout.scripts.length)
      sample = layout.by_script.first
      expect(sample).to be_a(Fontisan::Models::Audit::ScriptFeatures)
      expect(layout.scripts).to include(sample.script)
    end

    it "exposes presence flags" do
      expect(layout.has_gsub).to(satisfy { |v| [true, false].include?(v) })
      expect(layout.has_gpos).to(satisfy { |v| [true, false].include?(v) })
    end

    it "guarantees union of by_script feature lists matches features field" do
      gsub = layout.by_script.flat_map(&:gsub_features)
      gpos = layout.by_script.flat_map(&:gpos_features)
      expect((gsub + gpos).uniq.sort).to eq(layout.features)
    end
  end
end
