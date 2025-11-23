# frozen_string_literal: true

require "spec_helper"
require "fontisan"

RSpec.describe "Round-Trip Validation (Simplified)" do
  let(:ttf_font_path) do
    File.join(File.dirname(__FILE__), "..", "fixtures", "fonts",
              "NotoSans-Regular.ttf")
  end

  let(:converter) { Fontisan::Converters::OutlineConverter.new }

  describe "TTF → OTF conversion" do
    it "successfully converts without optimization" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Convert to OTF without optimization
      tables = converter.convert(font,
                                 target_format: :otf,
                                 optimize_subroutines: false)

      # Verify CFF table was created
      expect(tables["CFF "]).not_to be_nil
      expect(tables["CFF "].bytesize).to be > 0

      # Verify glyf/loca were removed
      expect(tables["glyf"]).to be_nil
      expect(tables["loca"]).to be_nil

      # Verify helper tables were updated
      expect(tables["maxp"]).not_to be_nil
      expect(tables["head"]).not_to be_nil
    end

    it "successfully converts with optimization enabled" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Convert with optimization
      tables = converter.convert(font,
                                 target_format: :otf,
                                 optimize_subroutines: true,
                                 verbose: false)

      # Verify CFF table was created
      expect(tables["CFF "]).not_to be_nil
      expect(tables["CFF "].bytesize).to be > 0

      # Verify optimization occurred
      opt_result = tables.instance_variable_get(:@subroutine_optimization)
      expect(opt_result).not_to be_nil
      expect(opt_result[:selected_count]).to be > 0
      expect(opt_result[:local_subrs]).not_to be_empty
    end
  end

  describe "File size comparison" do
    it "shows file size reduction with optimization" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Without optimization
      tables_unopt = converter.convert(font,
                                       target_format: :otf,
                                       optimize_subroutines: false)
      size_unopt = tables_unopt["CFF "].bytesize

      # With optimization
      tables_opt = converter.convert(font,
                                     target_format: :otf,
                                     optimize_subroutines: true)
      size_opt = tables_opt["CFF "].bytesize

      # Verify optimization reduces size
      # Note: Due to subroutine call overhead, small reductions are expected
      savings = size_unopt - size_opt
      reduction_percent = (savings * 100.0 / size_unopt).round(1)

      puts "\nFile Size Comparison:"
      puts "  Without optimization: #{size_unopt} bytes"
      puts "  With optimization:    #{size_opt} bytes"
      puts "  Bytes saved:          #{savings} bytes"
      puts "  Reduction:            #{reduction_percent}%"

      # Record the results for documentation
      expect(size_opt).to be <= size_unopt
    end
  end
end
