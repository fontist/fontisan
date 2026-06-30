# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"
require "tmpdir"

RSpec.describe Fontisan::Ufo::Compile::VariableTtf do
  let(:default_font) do
    font = Fontisan::Ufo::Font.new
    font.info.family_name = "TestVF"
    font.info.style_name = "Regular"
    font.info.version_major = 1
    font.info.version_minor = 0
    font.info.units_per_em = 1000

    notdef = Fontisan::Ufo::Glyph.new(name: ".notdef")
    notdef.width = 500
    font.glyphs[".notdef"] = notdef

    a = Fontisan::Ufo::Glyph.new(name: "A")
    a.add_unicode(0x41)
    a.width = 500
    a.add_contour(Fontisan::Ufo::Contour.new([
                                               Fontisan::Ufo::Point.new(x: 0, y: 0, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 100, y: 0, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 100, y: 100, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 0, y: 100, type: "line"),
                                             ]))
    font.glyphs["A"] = a
    font
  end

  let(:bold_font) do
    font = Fontisan::Ufo::Font.new
    font.info.family_name = "TestVF"
    font.info.style_name = "Bold"
    font.info.units_per_em = 1000

    notdef = Fontisan::Ufo::Glyph.new(name: ".notdef")
    notdef.width = 600
    font.glyphs[".notdef"] = notdef

    a = Fontisan::Ufo::Glyph.new(name: "A")
    a.add_unicode(0x41)
    a.width = 600
    a.add_contour(Fontisan::Ufo::Contour.new([
                                               Fontisan::Ufo::Point.new(x: 0, y: 0, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 120, y: 0, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 120, y: 120, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 0, y: 120, type: "line"),
                                             ]))
    font.glyphs["A"] = a
    font
  end

  let(:axes) do
    [{ tag: "wght", min: 100, default: 400, max: 900, name_id: 256, ordering: 0 }]
  end

  let(:masters) do
    [{ font: bold_font, axes: { "wght" => 1.0 } }]
  end

  let(:instances) do
    [
      { name_id: 257, flags: 0, coords: [400] },
      { name_id: 258, flags: 0, coords: [700] },
    ]
  end

  describe "#compile" do
    it "writes a TTF file with TrueType sfnt magic" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out-var.ttf")
        described_class.new(
          font: default_font, axes: axes, masters: masters, instances: instances,
        ).compile(output_path: path)
        expect(File.binread(path, 4).unpack1("N")).to eq(0x00010000)
      end
    end

    it "embeds fvar, gvar, HVAR, avar, STAT tables" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out-var.ttf")
        described_class.new(
          font: default_font, axes: axes, masters: masters, instances: instances,
          stat_axis_values: [
            { axis_index: 0, flags: 0, name_id: 259, value: 400.0 },
          ]
        ).compile(output_path: path)

        reopened = Fontisan::FontLoader.load(path)
        %w[fvar gvar HVAR avar STAT].each do |tag|
          expect(reopened.has_table?(tag)).to be(true), "expected #{tag} table"
        end
      end
    end

    it "embeds MVAR when default_metrics and master_metrics are supplied" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out-var.ttf")
        described_class.new(
          font: default_font, axes: axes, masters: masters,
          default_metrics: { hasc: 800 },
          master_metrics: [{ hasc: 900 }]
        ).compile(output_path: path)

        reopened = Fontisan::FontLoader.load(path)
        expect(reopened.has_table?("MVAR")).to be(true)
      end
    end

    it "skips MVAR when metric data is omitted" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out-var.ttf")
        described_class.new(
          font: default_font, axes: axes, masters: masters,
        ).compile(output_path: path)

        reopened = Fontisan::FontLoader.load(path)
        expect(reopened.has_table?("MVAR")).to be(false)
      end
    end
  end
end
