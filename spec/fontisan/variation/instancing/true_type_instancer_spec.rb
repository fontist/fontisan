# frozen_string_literal: true

require "spec_helper"

# Reference values below come from fontTools 4.68.0:
#   t = TTFont(path); del t["STAT"]   # (STAT only for the proportional font)
#   f = varLib.instancer.instantiateVariableFont(t, location, inplace: False)
#   bbox = min/max of f["glyf"][name].getCoordinates(f["glyf"])[0]
#   advance = f["hmtx"][name][0]
# Fontisan rounds each point to integers, so boxes agree within 1 unit.
RSpec.describe Fontisan::Variation::Instancing::TrueTypeInstancer do
  let(:fixture_dir) { File.expand_path("../../../fixtures/fonts/MonaSansVF", __dir__) }
  let(:mono_path) { File.join(fixture_dir, "MonaSansMonoVF[wght].ttf") }
  let(:prop_path) { File.join(fixture_dir, "MonaSansVF[wght,opsz].ttf") }
  let(:mono) { Fontisan::FontLoader.load(mono_path) }
  let(:prop) { Fontisan::FontLoader.load(prop_path) }

  def instance_tables(font, coords)
    described_class.new(font.table_data, coords).call
  end

  def load_static(tables)
    path = File.join(Dir.mktmpdir, "instance.ttf")
    File.binwrite(path, Fontisan::FontWriter.write_font(tables))
    Fontisan::FontLoader.load(path)
  end

  def glyph_box(font, char)
    gid = font.table("cmap").unicode_mappings.fetch(char.ord)
    loca = font.table("loca")
    loca.parse_with_context(font.table("head").index_to_loc_format,
                            font.table("maxp").num_glyphs)
    g = font.table("glyf").glyph_for(gid, loca, font.table("head"))
    [g.x_min, g.y_min, g.x_max, g.y_max]
  end

  def advance(font, char)
    gid = font.table("cmap").unicode_mappings.fetch(char.ord)
    hhea = font.table("hhea")
    hmtx = font.table("hmtx")
    hmtx.parse_with_context(hhea.number_of_h_metrics, font.table("maxp").num_glyphs)
    hmtx.metric_for(gid)[:advance_width]
  end

  def near(actual, expected)
    actual.zip(expected).all? { |a, e| (a - e).abs <= 1 }
  end

  it "produces different glyf data for wght=300 and wght=700" do
    light = instance_tables(mono, "wght" => 300)
    bold = instance_tables(mono, "wght" => 700)
    expect(light["glyf"]).not_to eq(bold["glyf"])
    expect(light["glyf"]).not_to eq(mono.table_data["glyf"])
  end

  it "returns a static font without variation tables" do
    tables = instance_tables(mono, "wght" => 700)
    expect(tables.keys & %w[fvar gvar avar HVAR MVAR STAT]).to be_empty
    static = load_static(tables)
    expect(static.has_table?("fvar")).to be(false)
    expect(static.has_table?("glyf")).to be(true)
  end

  describe "glyph bounding boxes (fontTools reference)" do
    {
      200 => { "H" => [102, 0, 516, 729], "O" => [50, -8, 568, 736] },
      300 => { "H" => [93, 0, 525, 729], "O" => [44, -8, 574, 737] },
      700 => { "H" => [71, 0, 547, 729], "O" => [30, -9, 589, 738] },
      900 => { "H" => [55, 0, 563, 729], "O" => [20, -10, 599, 739] },
    }.each do |wght, glyphs|
      glyphs.each do |char, expected|
        it "matches for #{char.inspect} at wght=#{wght} (mono)" do
          static = load_static(instance_tables(mono, "wght" => wght))
          expect(near(glyph_box(static, char), expected)).to be(true),
                                                             "got #{glyph_box(static, char)}, want #{expected}"
        end
      end
    end

    {
      [200, 0] => { "H" => [105, 0, 649, 729], "i" => [70, 0, 140, 719] },
      [900, 0] => { "H" => [62, 0, 720, 729], "i" => [49, 0, 254, 793] },
      [900, 100] => { "H" => [30, 0, 714, 729], "i" => [17, 0, 235, 775] },
    }.each do |(wght, opsz), glyphs|
      glyphs.each do |char, expected|
        it "matches for #{char.inspect} at wght=#{wght} opsz=#{opsz}" do
          static = load_static(instance_tables(prop, "wght" => wght, "opsz" => opsz))
          expect(near(glyph_box(static, char), expected)).to be(true),
                                                             "got #{glyph_box(static, char)}, want #{expected}"
        end
      end
    end
  end

  describe "advance widths" do
    it "changes with the axis where the font varies them" do
      thin = load_static(instance_tables(prop, "wght" => 200, "opsz" => 0))
      black = load_static(instance_tables(prop, "wght" => 900, "opsz" => 0))
      expect(advance(thin, "H")).to eq(754)
      expect(advance(black, "H")).to eq(782)
      expect(advance(thin, "W")).to eq(979)
      expect(advance(black, "W")).to eq(1022)
    end

    it "follows the opsz axis too" do
      static = load_static(instance_tables(prop, "wght" => 900, "opsz" => 100))
      expect(advance(static, "H")).to eq(744)
    end

    it "keeps the default-location advance unchanged" do
      static = load_static(instance_tables(mono, "wght" => 200))
      expect(advance(static, "H")).to eq(advance(mono, "H"))
    end
  end

  describe "OS/2 and name" do
    it "sets usWeightClass to the instance weight" do
      expect(load_static(instance_tables(mono, "wght" => 300)).table("OS/2").us_weight_class).to eq(300)
      expect(load_static(instance_tables(mono, "wght" => 700)).table("OS/2").us_weight_class).to eq(700)
    end

    it "uses the named-instance style for a named location" do
      names = load_static(instance_tables(mono, "wght" => 300)).table("name")
      expect(names.english_name(2)).to eq("Regular")
      expect(names.english_name(17)).to eq("Light")
      expect(names.english_name(4)).to include("Light")
      expect(names.english_name(6)).to end_with("-Light")
    end

    it "labels an unnamed location by its axis values" do
      names = load_static(instance_tables(mono, "wght" => 450)).table("name")
      expect(names.english_name(17)).to eq("Wght450")
    end
  end

  describe "validation" do
    it "rejects a value outside the axis range" do
      expect { instance_tables(mono, "wght" => 1000) }
        .to raise_error(Fontisan::InvalidCoordinatesError, /wght/)
    end

    it "rejects an axis the font does not have" do
      expect { instance_tables(mono, "wdth" => 100) }
        .to raise_error(Fontisan::InvalidAxisError, /wdth/)
    end

    it "rejects a static font" do
      static = Fontisan::FontLoader.load(
        File.expand_path("../../../fixtures/fonttools/TestTTF.ttf", __dir__),
      )
      expect { described_class.new(static.table_data, {}) }
        .to raise_error(Fontisan::MissingVariationTableError)
    end
  end
end
