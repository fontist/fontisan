# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/metrics"

RSpec.describe Fontisan::Audit::Extractors::Metrics do
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

  it "returns a single :metrics field" do
    fields = described_class.new.extract(ttf_context)
    expect(fields.keys).to contain_exactly(:metrics)
  end

  it "returns a Models::Audit::Metrics instance" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:metrics]).to be_a(Fontisan::Models::Audit::Metrics)
  end

  it "populates units_per_em from head" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:metrics].units_per_em).to be_between(16, 16384)
  end

  it "populates bbox fields from head" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:metrics].bbox_x_min).to be_an(Integer)
    expect(fields[:metrics].bbox_y_min).to be_an(Integer)
    expect(fields[:metrics].bbox_x_max).to be_an(Integer)
    expect(fields[:metrics].bbox_y_max).to be_an(Integer)
  end

  it "populates hhea ascent/descent/line_gap" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:metrics].hhea_ascent).to be_an(Integer)
    expect(fields[:metrics].hhea_descent).to be_an(Integer)
    expect(fields[:metrics].hhea_line_gap).to be_an(Integer)
  end

  it "populates OS/2 typo + win metrics" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:metrics].typo_ascender).to be_an(Integer)
    expect(fields[:metrics].typo_descender).to be_an(Integer)
    expect(fields[:metrics].win_ascent).to be_an(Integer)
    expect(fields[:metrics].win_descent).to be_an(Integer)
  end

  it "populates underline position/thickness from post" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:metrics].underline_position).to be_a(Float).or(be_nil)
    expect(fields[:metrics].underline_thickness).to be_a(Float).or(be_nil)
  end

  it "works for OTF/CFF fonts" do
    fields = described_class.new.extract(otf_context)
    expect(fields[:metrics]).to be_a(Fontisan::Models::Audit::Metrics)
    expect(fields[:metrics].units_per_em).to be_between(16, 16384)
  end

  it "populates subscript/superscript metrics from OS/2" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:metrics].subscript_x_size).to be_an(Integer)
    expect(fields[:metrics].superscript_y_offset).to be_an(Integer)
  end
end
