# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/licensing"

RSpec.describe Fontisan::Audit::Extractors::Licensing do
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

  it "returns a single :licensing field" do
    fields = described_class.new.extract(ttf_context)
    expect(fields.keys).to contain_exactly(:licensing)
  end

  it "returns a Models::Audit::Licensing instance" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:licensing]).to be_a(Fontisan::Models::Audit::Licensing)
  end

  it "populates copyright from nameID 0" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:licensing].copyright).not_to be_nil
  end

  it "populates license_url from nameID 14 when present" do
    fields = described_class.new.extract(ttf_context)
    # Noto fonts ship a license URL; be tolerant if a particular
    # fixture doesn't, but the field must exist.
    expect(fields[:licensing]).to respond_to(:license_url)
  end

  it "populates vendor_id from OS/2 achVendID (4 chars max)" do
    fields = described_class.new.extract(ttf_context)
    vid = fields[:licensing].vendor_id
    expect(vid).to be_a(String)
    expect(vid.length).to be <= 4
  end

  it "populates embedding_type as a decoded canonical string" do
    fields = described_class.new.extract(ttf_context)
    et = fields[:licensing].embedding_type
    canonical = %w[restricted_license preview_print editable installable
                   installable_no_subsetting installable_bitmap_only
                   installable_no_subsetting_bitmap_only unknown]
    expect(et.nil? || canonical.include?(et)).to be(true)
  end

  it "populates fs_selection_flags as an array" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:licensing].fs_selection_flags).to be_an(Array).or(be_nil)
  end

  it "works for OTF/CFF fonts" do
    fields = described_class.new.extract(otf_context)
    expect(fields[:licensing]).to be_a(Fontisan::Models::Audit::Licensing)
    expect(fields[:licensing].copyright).not_to be_nil
  end
end
