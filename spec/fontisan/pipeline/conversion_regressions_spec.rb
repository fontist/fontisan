# frozen_string_literal: true

require "spec_helper"

# Regressions found by fontist#435: conversions that failed inside the
# pipeline on valid input fonts.
RSpec.describe "Fontisan conversion regressions" do
  describe "conversions" do
    let(:fixtures) { File.expand_path("../../fixtures", __dir__) }
    let(:otf) { File.join(fixtures, "fonttools/TestOTF.otf") }
    let(:ttf) { File.join(fixtures, "fonttools/TestTTF.ttf") }
    let(:out_dir) { Dir.mktmpdir }

    def convert(input, target:, output:)
      Fontisan::Commands::ConvertCommand.new(input, to: target, output: output,
                                                    quiet: true).run
      output
    end

    it "converts otf to ttf with TrueType outlines and the same glyph count" do
      out = convert(otf, target: "ttf", output: File.join(out_dir, "o.ttf"))
      font = Fontisan::FontLoader.load(out)
      expect(font.has_table?("glyf")).to be(true)
      expect(font.has_table?("CFF ")).to be(false)
      expect(font.table("maxp").num_glyphs)
        .to eq(Fontisan::FontLoader.load(otf).table("maxp").num_glyphs)
    end

    it "converts woff to ttf" do
      woff = convert(ttf, target: "woff", output: File.join(out_dir, "t.woff"))
      out = convert(woff, target: "ttf", output: File.join(out_dir, "w.ttf"))
      font = Fontisan::FontLoader.load(out)
      expect(font.table_data["glyf"])
        .to eq(Fontisan::FontLoader.load(ttf).table_data["glyf"])
    end

    it "converts otf to woff2 keeping the CFF outlines" do
      out = convert(otf, target: "woff2", output: File.join(out_dir, "o.woff2"))
      expect(File.binread(out, 4)).to eq("wOF2")
      font = Fontisan::FontLoader.load(out)
      expect(font.has_table?("CFF ")).to be(true)
    end

    it "still converts ttf to woff2" do
      out = convert(ttf, target: "woff2", output: File.join(out_dir, "t.woff2"))
      expect(Fontisan::FontLoader.load(out).has_table?("glyf")).to be(true)
    end
  end

  describe Fontisan::Pipeline::Strategies::InstanceStrategy do
    it "is reachable through the Pipeline autoload and applies coordinates" do
      path = File.expand_path("../../fixtures/fonts/MonaSansVF/MonaSansMonoVF[wght].ttf", __dir__)
      font = Fontisan::FontLoader.load(path)
      light = described_class.new(coordinates: { "wght" => 300.0 }).resolve(font)
      bold = described_class.new(coordinates: { "wght" => 700.0 }).resolve(font)
      expect(light).not_to have_key("fvar")
      expect(light["glyf"]).not_to eq(bold["glyf"])
    end
  end

  describe "ConvertCommand coordinates" do
    let(:path) { File.expand_path("../../fixtures/fonts/MonaSansVF/MonaSansMonoVF[wght].ttf", __dir__) }
    let(:out_dir) { Dir.mktmpdir }

    def instance_at(coords, name)
      out = File.join(out_dir, name)
      Fontisan::Commands::ConvertCommand.new(path, to: "ttf", output: out,
                                                   coordinates: coords, quiet: true).run
      Fontisan::FontLoader.load(out)
    end

    it "writes a static instance whose outlines follow the coordinates" do
      light = instance_at("wght=300", "l.ttf")
      bold = instance_at("wght=700", "b.ttf")
      expect(light.has_table?("fvar")).to be(false)
      expect(light.table_data["glyf"]).not_to eq(bold.table_data["glyf"])
      expect(bold.table("OS/2").us_weight_class).to eq(700)
    end

    it "keeps the converted static instance valid" do
      instance_at("wght=300", "l.ttf")
      report = Fontisan.validate(File.join(out_dir, "l.ttf"), profile: :production)
      expect(report.errors.map(&:message)).to be_empty
    end
  end
end
