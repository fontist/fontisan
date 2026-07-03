# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/name"

RSpec.describe Fontisan::Ufo::Compile::Name, ".default_records" do
  let(:ufo) { Fontisan::Ufo }

  it "uses postscript_full_name for name ID 4 when set" do
    font = ufo::Font.new
    font.info.family_name = "Family"
    font.info.style_name = "Bold"
    font.info.postscript_full_name = "Custom Display Name"

    records = described_class.default_records(font)
    name_id_4 = records.find { |r| r[:name_id] == 4 }
    expect(name_id_4[:value]).to eq("Custom Display Name")
  end

  it "falls back to 'Family Subfamily' when postscript_full_name is unset" do
    font = ufo::Font.new
    font.info.family_name = "Family"
    font.info.style_name = "Bold"

    records = described_class.default_records(font)
    name_id_4 = records.find { |r| r[:name_id] == 4 }
    expect(name_id_4[:value]).to eq("Family Bold")
  end
end
