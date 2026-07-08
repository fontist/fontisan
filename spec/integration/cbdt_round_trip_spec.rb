# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fontisan/font_loader"
require "fontisan/font_writer"
require "fontisan/subset/builder"
require "fontisan/subset/options"

RSpec.describe "CBDT/CBLC subset round-trip", type: :integration do
  # Build synthetic CBDT + CBLC bytes for a 5-glyph range at a single
  # 16 ppem / 32-bit-depth strike. Each glyph gets a 4-byte marker
  # block so the spec can verify the bytes travel through subsetting
  # intact.
  let(:synthetic_color_tables) do
    gids = (10..14).to_a
    bitmaps = gids.map { |gid| "G#{gid}".ljust(4, "_").b }

    cbd_header = [3, 0].pack("nn")
    cbdt = cbd_header + bitmaps.join

    count = bitmaps.length
    image_data_offset = 4
    offsets = Array.new(count + 1) { |i| i * bitmaps.first.bytesize }
    ist = [1, 17, image_data_offset].pack("nnN") + offsets.pack("N*")
    ista = [gids.first, gids.last, 8].pack("nnN")

    bsm_offset = 8 + 48
    bsm_size = ista.bytesize + ist.bytesize
    bsm = [bsm_offset, bsm_size, 1, 0].pack("NNNN") +
      ("\x00" * 24) +
      [gids.first, gids.last, 16, 16, 32, 0].pack("nnCCCc")
    cblc = [0x00030000, 1].pack("NN") + bsm + ista + ist

    { "CBDT" => cbdt, "CBLC" => cblc }
  end

  let(:source_font_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }

  # Re-emit NotoSans with our synthetic CBDT/CBLC tables added, then
  # re-load so the table directory sees them. This is the closest to a
  # real-world "user added color bitmaps" scenario without requiring a
  # CBDT-bearing fixture font.
  let(:font) do
    base = Fontisan::FontLoader.load(source_font_path, font_index: 0,
                                                       mode: :full,
                                                       lazy: false)
    merged = base.table_data.dup.merge(synthetic_color_tables)
    rebuilt_bytes = Fontisan::FontWriter.write_font(merged)

    Tempfile.create(["cbdt-source", ".ttf"], binmode: true) do |tf|
      tf.write(rebuilt_bytes)
      tf.flush
      Fontisan::FontLoader.load(tf.path, font_index: 0, mode: :full,
                                         lazy: false)
    end
  end

  def reload(bytes)
    Tempfile.create(["cbdt-roundtrip", ".ttf"], binmode: true) do |tf|
      tf.write(bytes)
      tf.flush
      Fontisan::FontLoader.load(tf.path, font_index: 0, mode: :full,
                                         lazy: false)
    end
  end

  it "preserves CBDT and CBLC tables when subsetting with the web profile" do
    gids = [0, 10, 12] # .notdef + 2 color glyphs
    options = Fontisan::Subset::Options.new(profile: "web")
    subset_bytes = Fontisan::Subset::Builder.new(font, gids, options).build

    subset_font = reload(subset_bytes)
    expect(subset_font.table_data).to include("CBDT"),
                                      "web profile subset must retain CBDT"
    expect(subset_font.table_data).to include("CBLC"),
                                      "web profile subset must retain CBLC"

    cbdt = Fontisan::Tables::Cbdt.read(subset_font.table_data["CBDT"])
    cblc = Fontisan::Tables::Cblc.read(subset_font.table_data["CBLC"])

    source_cbdt = Fontisan::Tables::Cbdt.read(synthetic_color_tables["CBDT"])
    expect(cbdt.data_size).to be < source_cbdt.data_size,
                              "subset CBDT should drop unreferenced bitmaps"

    surviving = cblc.each_glyph_location.map do |loc|
      cbdt.bitmap_data_at(loc.cbdt_offset, loc.byte_length)
    end.sort
    expect(surviving).to eq(%w[G10_ G12_].map(&:b))
  end

  it "drops CBDT/CBLC when subsetting with the pdf profile" do
    gids = [0, 10]
    options = Fontisan::Subset::Options.new(profile: "pdf")
    subset_bytes = Fontisan::Subset::Builder.new(font, gids, options).build

    subset_font = reload(subset_bytes)
    expect(subset_font.table_data.key?("CBDT")).to be false
    expect(subset_font.table_data.key?("CBLC")).to be false
  end
end
