# frozen_string_literal: true

require_relative "support/corpus_paths"
require "tmpdir"

RSpec.describe Fontisan::Reference::TableDigests do
  def raw(id, tag)
    Fontisan::FontLoader.load(CorpusPaths.path(id), mode: :full).table_data[tag]
  end

  def glyph_count(id)
    Fontisan::Tables::Maxp.read(raw(id, "maxp")).num_glyphs
  end

  let(:cff2_id) { "source-sans-3-vf-upright-cff2" }
  let(:ttf_vf_id) { "noto-sans-vf-wdth-wght" }

  it "finds one CFF2 charstring per glyph" do
    expect(described_class.cff2_charstrings(raw(cff2_id, "CFF2")).size).to eq(glyph_count(cff2_id))
  end

  it "reports CFF2 outlines through the facade" do
    outlines = Fontisan::Reference.read(CorpusPaths.path(cff2_id), mode: :full).first["outlines"]

    expect(outlines).to include("kind" => "cff2", "count" => glyph_count(cff2_id))
  end

  it "covers every glyph in gvar and finds the shared tuples" do
    gvar = described_class.gvar(raw(ttf_vf_id, "gvar"))

    expect(gvar["glyph_count"]).to eq(glyph_count(ttf_vf_id))
    expect(gvar["glyphs_with_data"]).to be_between(1, gvar["glyph_count"])
    expect(gvar["shared_tuple_count"]).to be_positive
  end

  it "reads HVAR mappings and the variation store" do
    hvar = described_class.hvar(raw(ttf_vf_id, "HVAR"))

    expect(hvar["advance_mapping"]["map_count"]).to eq(glyph_count(ttf_vf_id))
    expect(hvar["item_variation_store"]["item_data_count"]).to be_positive
  end

  it "reads MVAR value records (Offset16 store, per the OpenType spec)" do
    data = raw(ttf_vf_id, "MVAR")
    tags = described_class.mvar(data)["value_records"].map { |r| r["tag"] }

    expect(tags).not_to be_empty
    expect(tags).to all(match(/\A[A-Za-z]{4}\z/))
    expect(tags.size).to eq(data.byteslice(8, 2).unpack1("n"))
    expect(tags).to include("xhgt")
  end

  it "reads STAT axes that include every fvar axis, with Fixed values as integers" do
    stat = described_class.stat(raw(ttf_vf_id, "STAT"))
    fvar_tags = Fontisan::FontLoader.load(CorpusPaths.path(ttf_vf_id), mode: :full)
      .table("fvar").axes.map { |a| a[:axis_tag] || a["axis_tag"] }

    expect(stat["axes"].map { |a| a["tag"] }).to include(*fvar_tags)
    expect(stat["axis_values"].map { |v| v["format"] }.uniq - [1, 2, 3, 4]).to be_empty
    expect(stat["axis_values"].flat_map { |v| v.values_at("value_raw", "nominal_raw") }.compact)
      .to all(be_an(Integer))
  end

  it "raises Truncated for a table cut short" do
    expect { described_class.gvar(raw(ttf_vf_id, "gvar").byteslice(0, 30)) }
      .to raise_error(described_class::Truncated)
  end

  it "records a truncated table as an error in the facade output" do
    Dir.mktmpdir do |dir|
      font = Fontisan::FontLoader.load(CorpusPaths.path(ttf_vf_id), mode: :full)
      tables = font.table_data.merge("gvar" => font.table_data["gvar"].byteslice(0, 30))
      file = File.join(dir, "cut.ttf")
      File.binwrite(file, Fontisan::FontWriter.write_font(tables))

      face = Fontisan::Reference.read(file, mode: :full).first
      expect(face["variation"]["gvar"]).to eq("error" => "Fontisan::Reference::TableDigests::Truncated")
    end
  end
end
