# frozen_string_literal: true

require "spec_helper"
require "fontisan"

# Verifies that every (from, to) pair declared as `implemented` in
# conversion_matrix.yml for web formats actually succeeds end-to-end through
# the pipeline, and that the resulting fonts carry the same identity as the
# source. Regression coverage for the FormatDetector ↔ matrix ↔ pipeline
# contract — these were previously broken (FormatDetector returned :unknown
# for WOFF/WOFF2, and the matrix missed woff↔woff2, woff→svg, woff2→svg).
RSpec.describe "Web format transcoding (matrix ↔ pipeline)" do
  let(:source_ttf) do
    font_fixture_path("MonaSans",
                      "fonts/static/ttf/MonaSansMono-Regular.ttf")
  end

  let(:output_dir) { File.join(__dir__, "../../tmp/web_transcoding") }

  before { FileUtils.mkdir_p(output_dir) }
  after  { FileUtils.rm_rf(output_dir) }

  def identity_of(path)
    info = Fontisan.info(path)
    { family_name: info.family_name, full_name: info.full_name,
      version: info.version }
  end

  describe "WOFF2 → WOFF (Brotli decode → zlib re-wrap)" do
    let(:woff2_path) { File.join(output_dir, "src.woff2") }
    let(:woff_path)  { File.join(output_dir, "out.woff") }

    before do
      Fontisan.convert(source_ttf, to: :woff2, output: woff2_path,
                                   brotli_quality: 11)
    end

    it "produces a valid WOFF file" do
      Fontisan.convert(woff2_path, to: :woff, output: woff_path)
      expect(File.exist?(woff_path)).to be(true)
      expect(File.binread(woff_path, 4)).to eq("wOFF")
    end

    it "preserves font identity" do
      Fontisan.convert(woff2_path, to: :woff, output: woff_path)
      expect(identity_of(woff_path)).to eq(identity_of(source_ttf))
    end

    it "is reported in the conversion matrix as supported" do
      converter = Fontisan::Converters::FormatConverter.new
      expect(converter.supported?(:woff2, :woff)).to be(true)
    end
  end

  describe "WOFF → WOFF2 (zlib decode → Brotli re-wrap)" do
    let(:woff_path)  { File.join(output_dir, "src.woff") }
    let(:woff2_path) { File.join(output_dir, "out.woff2") }

    before do
      Fontisan.convert(source_ttf, to: :woff, output: woff_path,
                                   zlib_level: 9)
    end

    it "produces a valid WOFF2 file" do
      Fontisan.convert(woff_path, to: :woff2, output: woff2_path)
      expect(File.exist?(woff2_path)).to be(true)
      expect(File.binread(woff2_path, 4)).to eq("wOF2")
    end

    it "preserves font identity" do
      Fontisan.convert(woff_path, to: :woff2, output: woff2_path)
      expect(identity_of(woff2_path)).to eq(identity_of(source_ttf))
    end

    it "compresses smaller than the WOFF source (Brotli < zlib)" do
      Fontisan.convert(woff_path, to: :woff2, output: woff2_path)
      expect(File.size(woff2_path)).to be < File.size(woff_path)
    end

    it "is reported in the conversion matrix as supported" do
      converter = Fontisan::Converters::FormatConverter.new
      expect(converter.supported?(:woff, :woff2)).to be(true)
    end
  end

  describe "WOFF → SVG and WOFF2 → SVG" do
    let(:woff_path)  { File.join(output_dir, "src.woff") }
    let(:woff2_path) { File.join(output_dir, "src.woff2") }

    before do
      Fontisan.convert(source_ttf, to: :woff, output: woff_path)
      Fontisan.convert(source_ttf, to: :woff2, output: woff2_path)
    end

    it "renders SVG from WOFF" do
      out = File.join(output_dir, "from_woff.svg")
      Fontisan.convert(woff_path, to: :svg, output: out)
      expect(File.binread(out, 5)).to eq("<?xml")
    end

    it "renders SVG from WOFF2" do
      out = File.join(output_dir, "from_woff2.svg")
      Fontisan.convert(woff2_path, to: :svg, output: out)
      expect(File.binread(out, 5)).to eq("<?xml")
    end
  end

  describe "FormatDetector now recognizes web font objects" do
    let(:woff_path)  { File.join(output_dir, "src.woff") }
    let(:woff2_path) { File.join(output_dir, "src.woff2") }

    before do
      Fontisan.convert(source_ttf, to: :woff, output: woff_path)
      Fontisan.convert(source_ttf, to: :woff2, output: woff2_path)
    end

    it "reports :woff (not :unknown) for a WOFF source" do
      detector = Fontisan::Pipeline::FormatDetector.new(woff_path)
      detector.detect
      expect(detector.detect_format).to eq(:woff)
    end

    it "reports :woff2 (not :unknown) for a WOFF2 source" do
      detector = Fontisan::Pipeline::FormatDetector.new(woff2_path)
      detector.detect
      expect(detector.detect_format).to eq(:woff2)
    end
  end
end
