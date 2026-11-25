# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Fontisan::Converters::Type1Converter do
  let(:converter) { described_class.new }

  def fixture(name)
    File.expand_path("../../fixtures/fonttools/#{name}", __dir__)
  end

  def corpus_font_id(id, name)
    File.expand_path("../../../corpus/fonts/#{id}/#{name}", __dir__)
  end

  # The main rake workflow runs without the corpus; the parity suites skip.
  def corpus_pfb
    corpus_font_id("fonttools-test-t1-pfb", "TestT1-Regular.pfb")
  end

  def convert_and_write(path, target, dir)
    out = File.join(dir, "out#{target == :type1 ? '.pfb' : ".#{target}"}")
    Fontisan::Reference.convert(path, to: target, output: out)
    out
  end

  it "converts the corpus PFB to a loadable OTF" do
    skip "corpus not fetched" unless File.file?(corpus_pfb)
    Dir.mktmpdir do |dir|
      out = convert_and_write(corpus_pfb, :otf, dir)
      font = Fontisan::FontLoader.load(out, mode: :full)
      expect(font).to be_a(Fontisan::OpenTypeFont)
      expect(font.table("maxp").num_glyphs).to eq(6)
      expect(font.table("CFF ").glyph_count).to eq(6)
    end
  end

  it "converts the corpus PFB to a loadable TTF" do
    skip "corpus not fetched" unless File.file?(corpus_pfb)
    Dir.mktmpdir do |dir|
      out = convert_and_write(corpus_pfb, :ttf, dir)
      font = Fontisan::FontLoader.load(out, mode: :full)
      expect(font).to be_a(Fontisan::TrueTypeFont)
      expect(font.table("maxp").num_glyphs).to eq(6)
      expect(font.table("glyf").raw_data.bytesize).to be_positive
    end
  end

  it "converts a TTF to a PFB that parses back to the same CharStrings" do
    Dir.mktmpdir do |dir|
      source = Fontisan::FontLoader.load(fixture("TestTTF.ttf"), mode: :full)
      out = convert_and_write(fixture("TestTTF.ttf"), :type1, dir)
      pfb = Fontisan::FontLoader.load(out, mode: :full)
      expect(pfb).to be_a(Fontisan::Type1Font)
      pfb.decrypt!
      pfb.parse_dictionaries!
      expect(pfb.font_name).to eq("TestTTF-Regular")

      scaler = Fontisan::Type1::UPMScaler.new(source, target_upm: 1000)
      plain = Fontisan::Type1::TTFToType1Converter.convert(source, scaler,
                                                           Fontisan::Type1::Encodings::AdobeStandard)
      names = source.table("post").glyph_names
      expect(pfb.charstrings.count).to eq(plain.size)
      expect(pfb.charstrings.charstrings.to_a).to eq(plain.to_a.map { |gid, cs| [names[gid] || "glyph#{gid}", cs] })
    end
  end

  it "converts an OTF to a PFB that parses back with the source's outlines" do
    Dir.mktmpdir do |dir|
      out = convert_and_write(fixture("TestOTF.otf"), :type1, dir)
      pfb = Fontisan::FontLoader.load(out, mode: :full)
      pfb.decrypt!
      pfb.parse_dictionaries!
      expect(pfb.font_name).to eq("TestOTF-Regular")
      expect(pfb.charstrings.count).to eq(6)
      expect(pfb.font_dictionary.font_bbox).to eq([50, 0, 668, 750])
    end
  end

  it "generates byte-identical output for the same input" do
    first = Fontisan::Type1::PFBGenerator.generate(Fontisan::FontLoader.load(fixture("TestTTF.ttf"), mode: :full))
    second = Fontisan::Type1::PFBGenerator.generate(Fontisan::FontLoader.load(fixture("TestTTF.ttf"), mode: :full))
    expect(first).to eq(second)
  end

  it "frames the PFB with the parser's chunk markers" do
    pfb = Fontisan::Type1::PFBGenerator.generate(Fontisan::FontLoader.load(fixture("TestTTF.ttf"), mode: :full))
    expect(pfb.byteslice(0, 2)).to eq("\x80\x01".b)
    expect(pfb.byteslice(-6, 2)).to eq("\x80\x03".b)
    expect(pfb).to include("currentfile eexec")
  end

  it "rescales CFF coordinates to 1000 upm on the reverse direction" do
    font = Fontisan::FontLoader.load(fixture("TestOTF.otf"), mode: :full)
    upm = font.table("head").units_per_em
    scale = 1000.0 / upm
    head = font.table("head")
    scaled = [head.x_min, head.y_min, head.x_max, head.y_max].map { |v| (v * scale).round }

    Dir.mktmpdir do |dir|
      out = convert_and_write(fixture("TestOTF.otf"), :type1, dir)
      pfb = Fontisan::FontLoader.load(out, mode: :full)
      expect(pfb.font_dictionary.font_bbox).to eq(scaled)
    end
  end
end
