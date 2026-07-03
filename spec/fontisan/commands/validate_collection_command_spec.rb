# frozen_string_literal: true

require "spec_helper"
require "fontisan/commands/validate_collection_command"
require "fontisan/stitcher"
require "tmpdir"

RSpec.describe Fontisan::Commands::ValidateCollectionCommand do
  let(:ufo) { Fontisan::Ufo }
  let(:ttc_path) do
    latin = make_font_with("A", 0x41)
    cjk   = make_font_with("uni4E00", 0x4E00)

    stitcher = Fontisan::Stitcher.new
    stitcher.add_source(:latin, latin)
    stitcher.add_source(:cjk, cjk)
    stitcher.include_notdef(from: :latin, into: :latin)
    stitcher.include_codepoints([0x41], from: :latin, into: :latin)
    stitcher.include_notdef(from: :cjk, into: :cjk)
    stitcher.include_codepoints([0x4E00], from: :cjk, into: :cjk)

    path = File.join(Dir.mktmpdir, "out.ttc")
    stitcher.write_collection(path, format: :ttf).path
  end

  def make_font_with(name, cp)
    font = ufo::Font.new
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

    g = ufo::Glyph.new(name: name)
    g.width = 500
    g.add_unicode(cp)
    g.add_contour(ufo::Contour.new([
                                     ufo::Point.new(x: 0, y: 0, type: "line"),
                                     ufo::Point.new(x: 100, y: 0,   type: "line"),
                                     ufo::Point.new(x: 100, y: 100, type: "line"),
                                   ]))
    font.glyphs[name] = g
    font
  end

  it "exits 0 on a valid collection with no specific expectations" do
    cmd = described_class.new(input: ttc_path)
    expect { cmd.run }.to output(/all 2 faces within/).to_stdout
    expect(cmd.checks.map(&:name)).to eq([:glyph_cap])
    expect(cmd.checks).to all(satisfy(&:passed))
  end

  it "exits 1 when --expected-faces doesn't match" do
    # Silence stdout for the failure-path report.
    cmd = described_class.new(input: ttc_path, expected_faces: 5)
    expect { suppress_stdout { cmd.run } }.to change { cmd.checks }.from(nil).to(anything)
    face_count_check = cmd.checks.find { |c| c.name == :face_count }
    expect(face_count_check.passed).to be(false)
    expect(face_count_check.message).to include("expected 5 faces, got 2")
  end

  it "exits 1 when --max-glyphs is below a face's glyph count" do
    cmd = described_class.new(input: ttc_path, max_glyphs: 1)
    exit_code = suppress_stdout { cmd.run }
    expect(exit_code).to eq(1)
    glyph_cap_check = cmd.checks.find { |c| c.name == :glyph_cap }
    expect(glyph_cap_check.passed).to be(false)
  end

  it "exits 1 when --expected-cmap-union is above actual" do
    cmd = described_class.new(input: ttc_path, expected_cmap_union: 1_000)
    exit_code = suppress_stdout { cmd.run }
    expect(exit_code).to eq(1)
    cmap_union_check = cmd.checks.find { |c| c.name == :cmap_union }
    expect(cmap_union_check.passed).to be(false)
  end

  it "exits 0 when all checks pass with explicit expectations" do
    cmd = described_class.new(input: ttc_path,
                              expected_faces: 2,
                              expected_cmap_union: 2)
    exit_code = nil
    suppress_stdout { exit_code = cmd.run }
    expect(exit_code).to eq(0)
  end

  it "raises ArgumentError for a non-collection file" do
    # Reader delegates format detection to FontLoader; a real TTF is not
    # a collection, so the constructor must reject it. Use the first face
    # of our TTC fixture extracted to a single TTF.
    single_ttf = File.join(Dir.mktmpdir, "single.ttf")
    face = Fontisan::FontLoader.load(ttc_path)
    Fontisan::FontWriter.write_to_file(
      { "head" => face.table("head").raw_data },
      single_ttf,
      sfnt_version: 0x00010000,
    )

    expect do
      described_class.new(input: single_ttf).run
    end.to raise_error(ArgumentError, /not a TTC\/OTC\/dfont/)
  end

  private

  def suppress_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
