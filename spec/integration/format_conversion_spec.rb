# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Format Conversion Integration" do
  let(:ttf_font_path) { "spec/fixtures/fonts/noto-sans/NotoSans-Regular.ttf" }
  let(:output_dir) { "spec/fixtures/output" }

  before do
    FileUtils.mkdir_p(output_dir)
  end

  after do
    # Clean up generated files
    Dir.glob("#{output_dir}/*").each { |f| FileUtils.rm_f(f) }
  end

  describe "same-format conversions" do
    context "TTF to TTF" do
      let(:output_path) { File.join(output_dir, "ttf_copy.ttf") }

      it "creates a valid copy of the font" do
        converter = Fontisan::Converters::FormatConverter.new
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, :ttf)
        Fontisan::FontWriter.write_to_file(tables, output_path)

        expect(File.exist?(output_path)).to be true
        expect(File.size(output_path)).to be > 0
      end

      it "preserves all tables" do
        converter = Fontisan::Converters::FormatConverter.new
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, :ttf)

        # Verify essential tables are present
        expect(tables).to include("head", "hhea", "maxp")
        expect(tables).to include("glyf", "loca")
      end

      it "produces a font that can be reloaded" do
        converter = Fontisan::Converters::FormatConverter.new
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, :ttf)
        Fontisan::FontWriter.write_to_file(tables, output_path)

        # Should be able to reload the converted font
        reloaded = Fontisan::FontLoader.load(output_path)
        expect(reloaded).not_to be_nil
        expect(reloaded.table("head")).not_to be_nil
      end

      it "preserves font metrics" do
        converter = Fontisan::Converters::FormatConverter.new
        original_font = Fontisan::FontLoader.load(ttf_font_path)
        original_head = original_font.table("head")
        original_units = original_head.units_per_em

        tables = converter.convert(original_font, :ttf)
        Fontisan::FontWriter.write_to_file(tables, output_path)

        converted_font = Fontisan::FontLoader.load(output_path)
        converted_head = converted_font.table("head")

        expect(converted_head.units_per_em).to eq(original_units)
      end
    end
  end

  describe "cross-format conversions" do
    context "TTF to OTF" do
      let(:output_path) { File.join(output_dir, "ttf_to_otf.otf") }

      # NOTE: NotoSans-Regular.ttf contains compound glyphs
      # Compound glyph support has been implemented in Phase 1 Week 5
      it "successfully converts fonts with compound glyphs" do
        converter = Fontisan::Converters::FormatConverter.new
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, :otf)

        expect(tables).to have_key("CFF ")
        expect(tables).not_to have_key("glyf")
        expect(tables).not_to have_key("loca")
      end

      it "produces valid CFF output for compound glyphs" do
        converter = Fontisan::Converters::FormatConverter.new
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, :otf)

        # CFF table should be present and valid
        expect(tables["CFF "]).to be_a(String)
        expect(tables["CFF "].encoding).to eq(Encoding::BINARY)
        expect(tables["CFF "].bytesize).to be > 0
      end
    end
  end

  describe "CLI integration" do
    let(:command) { Fontisan::Commands::ConvertCommand }
    let(:output_path) { File.join(output_dir, "cli_output.ttf") }

    it "converts font via CLI command" do
      cmd = command.new(
        ttf_font_path,
        to: "ttf",
        output: output_path,
      )

      result = cmd.run

      expect(result[:success]).to be true
      expect(File.exist?(output_path)).to be true
    end

    it "reports conversion statistics" do
      cmd = command.new(
        ttf_font_path,
        to: "ttf",
        output: output_path,
      )

      result = cmd.run

      expect(result).to include(:input_size, :output_size)
      expect(result[:input_size]).to be > 0
      expect(result[:output_size]).to be > 0
    end

    it "detects source format automatically" do
      cmd = command.new(
        ttf_font_path,
        to: "ttf",
        output: output_path,
      )

      result = cmd.run

      expect(result[:source_format]).to eq(:ttf)
    end
  end

  describe "conversion matrix" do
    let(:converter) { Fontisan::Converters::FormatConverter.new }

    it "loads conversion matrix from config file" do
      expect(converter.conversion_matrix).not_to be_nil
      expect(converter.conversion_matrix).to have_key("conversions")
    end

    it "lists all supported conversions" do
      conversions = converter.all_conversions
      expect(conversions).not_to be_empty
      expect(conversions).to all(have_key(:from))
      expect(conversions).to all(have_key(:to))
    end

    it "validates conversions against matrix" do
      expect(converter.supported?(:ttf, :ttf)).to be true
      expect(converter.supported?(:otf, :otf)).to be true
      expect(converter.supported?(:ttf, :unknown)).to be false
    end
  end

  describe "error handling" do
    let(:converter) { Fontisan::Converters::FormatConverter.new }

    it "provides helpful error for unsupported conversion" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      expect do
        converter.convert(font, :unknown)
      end.to raise_error(Fontisan::Error, /not supported/)
    end

    it "lists available targets in error message" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      begin
        converter.convert(font, :unknown)
      rescue Fontisan::Error => e
        expect(e.message).to include("Available targets")
      end
    end

    it "handles missing required tables gracefully" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Mock a font missing required tables
      allow(font).to receive(:has_table?).with("glyf").and_return(true)
      allow(font).to receive(:has_table?).with("loca").and_return(true)
      allow(font).to receive(:has_table?).with("CFF ").and_return(false)
      allow(font).to receive(:has_table?).with("CFF2").and_return(false)
      allow(font).to receive(:has_table?).with("head").and_return(false)
      allow(font).to receive(:has_table?).with("hhea").and_return(true)
      allow(font).to receive(:has_table?).with("maxp").and_return(true)
      allow(font).to receive(:table).with("glyf").and_return(double)
      allow(font).to receive(:table).with("loca").and_return(double)
      allow(font).to receive(:table).with("head").and_return(nil)

      converter = Fontisan::Converters::OutlineConverter.new

      expect do
        converter.validate(font, :otf)
      end.to raise_error(Fontisan::MissingTableError, /head/)
    end
  end

  describe "SVG font generation" do
    context "TTF to SVG" do
      let(:output_path) { File.join(output_dir, "ttf_to_svg.svg") }

      it "generates valid SVG font file" do
        converter = Fontisan::Converters::FormatConverter.new
        font = Fontisan::FontLoader.load(ttf_font_path)

        result = converter.convert(font, :svg)
        expect(result).to have_key(:svg_xml)

        File.write(output_path, result[:svg_xml])

        expect(File.exist?(output_path)).to be true
        expect(File.size(output_path)).to be > 0
      end

      it "generates valid SVG XML structure" do
        converter = Fontisan::Converters::FormatConverter.new
        font = Fontisan::FontLoader.load(ttf_font_path)

        result = converter.convert(font, :svg)
        svg_xml = result[:svg_xml]

        expect(svg_xml).to include('<?xml version="1.0"')
        expect(svg_xml).to include("<svg xmlns=")
        expect(svg_xml).to include("<defs>")
        expect(svg_xml).to include("<font")
        expect(svg_xml).to include("<font-face")
        expect(svg_xml).to include("</svg>")
      end

      it "includes glyphs in SVG" do
        converter = Fontisan::Converters::FormatConverter.new
        font = Fontisan::FontLoader.load(ttf_font_path)

        result = converter.convert(font, :svg)
        svg_xml = result[:svg_xml]

        expect(svg_xml).to include("<glyph")
        expect(svg_xml).to include("<missing-glyph")
      end

      it "converts via CLI command" do
        cmd = Fontisan::Commands::ConvertCommand.new(
          ttf_font_path,
          to: "svg",
          output: output_path,
        )

        result = cmd.run

        expect(result[:success]).to be true
        expect(File.exist?(output_path)).to be true

        # Verify it's valid XML
        svg_content = File.read(output_path)
        expect(svg_content).to include("<?xml version")
      end
    end
  end

  describe "strategy pattern" do
    let(:converter) { Fontisan::Converters::FormatConverter.new }

    it "uses TableCopier for same-format conversions" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      expect_any_instance_of(Fontisan::Converters::TableCopier)
        .to receive(:convert).and_call_original

      converter.convert(font, :ttf)
    end

    it "uses OutlineConverter for cross-format conversions" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      expect_any_instance_of(Fontisan::Converters::OutlineConverter)
        .to receive(:convert).and_call_original

      tables = converter.convert(font, :otf)
      expect(tables).to have_key("CFF ")
    end

    it "uses SvgGenerator for SVG conversions" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      expect_any_instance_of(Fontisan::Converters::SvgGenerator)
        .to receive(:convert).and_call_original

      converter.convert(font, :svg)
    end

    it "selects strategy dynamically based on formats" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Same format = TableCopier
      tables = converter.convert(font, :ttf)
      expect(tables).to include("glyf")

      # Cross-format = OutlineConverter
      tables = converter.convert(font, :otf)
      expect(tables).to have_key("CFF ")

      # SVG generation = SvgGenerator
      result = converter.convert(font, :svg)
      expect(result).to have_key(:svg_xml)
    end
  end
end
