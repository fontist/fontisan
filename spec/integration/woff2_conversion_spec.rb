# frozen_string_literal: true

require "spec_helper"
require "fontisan/font_loader"
require "fontisan/converters/woff2_encoder"
require "fontisan/commands/convert_command"
require "tempfile"

RSpec.describe "WOFF2 Conversion Integration", type: :integration do
  let(:test_font_path) do
    font_fixture_path("NotoSans", "NotoSans-Regular.ttf")
  end

  let(:output_dir) do
    File.join(File.dirname(__FILE__), "..", "fixtures", "output")
  end

  before do
    FileUtils.mkdir_p(output_dir)
  end

  after do
    # Clean up output files created during tests
    Dir.glob(File.join(output_dir, "*.woff2")).each do |file|
      FileUtils.rm_f(file)
    end
  end

  describe "TTF to WOFF2 conversion" do
    let(:output_path) { File.join(output_dir, "test_output.woff2") }

    it "converts TTF font to WOFF2 format" do
      font = Fontisan::FontLoader.load(test_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result = encoder.convert(font)

      expect(result).to have_key(:woff2_binary)
      expect(result[:woff2_binary]).to be_a(String)
      expect(result[:woff2_binary].bytesize).to be > 0
    end

    it "produces valid WOFF2 signature" do
      font = Fontisan::FontLoader.load(test_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result = encoder.convert(font)
      binary = result[:woff2_binary]

      signature = binary[0, 4].unpack1("N")
      expect(signature).to eq(0x774F4632) # 'wOF2'
    end

    it "produces smaller file than original TTF" do
      font = Fontisan::FontLoader.load(test_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result = encoder.convert(font)
      woff2_size = result[:woff2_binary].bytesize
      ttf_size = File.size(test_font_path)

      # WOFF2 should be significantly smaller due to Brotli compression
      expect(woff2_size).to be < ttf_size

      # Calculate compression ratio
      ratio = woff2_size.to_f / ttf_size

      # Typically WOFF2 achieves 30-50% compression
      expect(ratio).to be < 0.8 # At least 20% compression
    end

    it "writes WOFF2 file successfully" do
      font = Fontisan::FontLoader.load(test_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result = encoder.convert(font)
      File.binwrite(output_path, result[:woff2_binary])

      expect(File.exist?(output_path)).to be true
      expect(File.size(output_path)).to be > 0
    end

    it "preserves font flavor information" do
      font = Fontisan::FontLoader.load(test_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result = encoder.convert(font)
      binary = result[:woff2_binary]

      # Read flavor from WOFF2 header (offset 4, 4 bytes)
      flavor = binary[4, 4].unpack1("N")
      expect(flavor).to eq(0x00010000) # TrueType flavor
    end
  end

  describe "using ConvertCommand" do
    let(:output_path) { File.join(output_dir, "command_output.woff2") }

    it "converts font using command interface" do
      command = Fontisan::Commands::ConvertCommand.new(
        test_font_path,
        to: "woff2",
        output: output_path,
      )

      result = command.run

      expect(result[:success]).to be true
      expect(File.exist?(output_path)).to be true
      expect(result[:target_format]).to eq(:woff2)
    end

    it "reports file sizes" do
      command = Fontisan::Commands::ConvertCommand.new(
        test_font_path,
        to: "woff2",
        output: output_path,
      )

      result = command.run

      expect(result[:input_size]).to be > 0
      expect(result[:output_size]).to be > 0
      expect(result[:output_size]).to be < result[:input_size]
    end
  end

  describe "WOFF2 structure validation" do
    it "has correct header size" do
      font = Fontisan::FontLoader.load(test_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result = encoder.convert(font)
      binary = result[:woff2_binary]

      # WOFF2 header is exactly 48 bytes
      expect(binary.bytesize).to be >= 48
    end

    it "includes table directory" do
      font = Fontisan::FontLoader.load(test_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result = encoder.convert(font)
      binary = result[:woff2_binary]

      # Read num_tables from header (offset 12, 2 bytes)
      num_tables = binary[12, 2].unpack1("n")
      expect(num_tables).to be > 0
      expect(num_tables).to be < 100 # Reasonable upper limit
    end

    it "includes compressed data" do
      font = Fontisan::FontLoader.load(test_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result = encoder.convert(font)
      binary = result[:woff2_binary]

      # Read totalCompressedSize from header (offset 24, 4 bytes)
      compressed_size = binary[24, 4].unpack1("N")
      expect(compressed_size).to be > 0
    end
  end

  describe "compression quality" do
    it "accepts custom quality parameter" do
      font = Fontisan::FontLoader.load(test_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result_low = encoder.convert(font, quality: 5)
      result_high = encoder.convert(font, quality: 11)

      # Both should produce valid output
      expect(result_low[:woff2_binary].bytesize).to be > 0
      expect(result_high[:woff2_binary].bytesize).to be > 0

      # Higher quality should generally produce smaller output
      # (though not guaranteed for all data)
      expect(result_high[:woff2_binary].bytesize).to be <= result_low[:woff2_binary].bytesize + 100
    end
  end

  describe "error handling" do
    it "raises error for missing output path" do
      expect do
        Fontisan::Commands::ConvertCommand.new(
          test_font_path,
          to: "woff2",
        ).run
      end.to raise_error(ArgumentError, /Output path is required/)
    end
  end

  describe "with different font types" do
    let(:cff_font_path) do
      font_fixture_path("Libertinus", "static/OTF/LibertinusSerif-Regular.otf")
    end

    it "converts CFF/OTF font to WOFF2" do
      font = Fontisan::FontLoader.load(cff_font_path)
      encoder = Fontisan::Converters::Woff2Encoder.new

      result = encoder.convert(font)

      expect(result[:woff2_binary]).to be_a(String)
      expect(result[:woff2_binary].bytesize).to be > 0

      # Check CFF flavor
      binary = result[:woff2_binary]
      flavor = binary[4, 4].unpack1("N")
      expect(flavor).to eq(0x4F54544F) # 'OTTO' for CFF
    end
  end

  describe "real-world usage patterns" do
    it "works in a typical web font generation workflow" do
      # 1. Load font
      font = Fontisan::FontLoader.load(test_font_path)

      # 2. Convert to WOFF2
      encoder = Fontisan::Converters::Woff2Encoder.new
      result = encoder.convert(font, quality: 11)

      # 3. Write to file
      output_path = File.join(output_dir, "webfont.woff2")
      File.binwrite(output_path, result[:woff2_binary])

      # 4. Verify result
      expect(File.exist?(output_path)).to be true

      original_size = File.size(test_font_path)
      compressed_size = File.size(output_path)
      ((1 - (compressed_size.to_f / original_size)) * 100).round(1)

      expect(compressed_size).to be < original_size
    end
  end
end
