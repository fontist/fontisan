# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/variation_detail"
require "fontisan/audit/context"

RSpec.describe Fontisan::Audit::Extractors::VariationDetail do
  let(:variable_ttf_path) do
    font_fixture_path("MonaSans",
                      "fonts/variable/MonaSansVF[wdth,wght,opsz,ital].ttf")
  end
  let(:static_ttf_path) do
    font_fixture_path("NotoSans", "NotoSans-Regular.ttf")
  end

  let(:variable_context) do
    font = Fontisan::FontLoader.load(variable_ttf_path, mode: :full)
    Fontisan::Audit::Context.new(
      font: font, font_path: variable_ttf_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  let(:static_context) do
    font = Fontisan::FontLoader.load(static_ttf_path, mode: :full)
    Fontisan::Audit::Context.new(
      font: font, font_path: static_ttf_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  it "returns variation key only" do
    fields = described_class.new.extract(variable_context)
    expect(fields.keys).to contain_exactly(:variation)
  end

  context "with a variable font" do
    let(:fields) { described_class.new.extract(variable_context) }

    it "returns a VariationDetail model" do
      expect(fields[:variation]).to be_a(Fontisan::Models::Audit::VariationDetail)
    end

    it "exposes axes" do
      axes = fields[:variation].axes
      expect(axes).to be_an(Array)
      expect(axes).not_to be_empty
      tags = axes.map(&:tag)
      expect(tags).to include("wght")
      expect(tags).to include("wdth")
    end

    it "exposes axis min/default/max floats" do
      wght = fields[:variation].axes.find { |a| a.tag == "wght" }
      expect(wght.min_value).to be_a(Float)
      expect(wght.default_value).to be_a(Float)
      expect(wght.max_value).to be_a(Float)
      expect(wght.min_value).to be <= wght.default_value
      expect(wght.default_value).to be <= wght.max_value
    end

    it "exposes named instances" do
      instances = fields[:variation].named_instances
      expect(instances).to be_an(Array)
      expect(instances).not_to be_empty
      expect(instances.first).to be_a(Fontisan::Models::Audit::NamedInstance)
      expect(instances.first.subfamily_name).to be_a(String)
      expect(instances.first.coordinates).to match(/=/)
    end

    it "exposes presence flags as booleans" do
      variation = fields[:variation]
      %i[has_avar has_cvar has_hvar has_vvar has_mvar has_gvar].each do |flag|
        expect(variation.public_send(flag)).to(satisfy { |v| [true, false].include?(v) })
      end
    end
  end

  context "with a non-variable font" do
    it "returns nil variation" do
      fields = described_class.new.extract(static_context)
      expect(fields[:variation]).to be_nil
    end
  end
end
