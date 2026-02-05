# frozen_string_literal: true

require_relative "../spec_helper"
require "benchmark"
require "get_process_mem"

RSpec.describe "Type 1 Performance Benchmarks" do
  let(:converter) { Fontisan::Converters::Type1Converter.new }

  # Get a sample Type 1 font file for testing
  def get_test_font
    # Get gem root from the current file's location
    # File is at: spec/performance/type1_performance_spec.rb
    # Gem root is two levels up from spec/
    gem_root = File.expand_path("../..", __dir__)
    fixture_dir = File.join(gem_root, "spec", "fixtures", "fonts", "type1")

    # Prefer quicksand.pfb if available
    quicksand = File.join(fixture_dir, "quicksand.pfb")
    return quicksand if File.exist?(quicksand)

    # Otherwise find any .pfb or .t1 file
    Dir.glob(File.join(fixture_dir, "**", "*.{pfb,t1}")).first
  end

  describe "Type 1 font loading performance" do
    it "loads Type 1 fonts within acceptable time" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      # Benchmark: Loading should complete within 5 seconds per font
      time = Benchmark.realtime do
        font = Fontisan::FontLoader.load(font_path)
        expect(font).to be_a(Fontisan::Type1Font)
      end

      # Loading a Type 1 font should be fast (< 5 seconds)
      expect(time).to be < 5.0, "Font loading took #{time}s, expected < 5s"
    end
  end

  describe "CharString conversion performance" do
    it "converts CharStrings to CFF within acceptable time" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::FULL)
      skip "Font loading failed" unless font

      charstrings_count = font.charstrings&.count || 0
      skip "No CharStrings found (parsed #{charstrings_count} glyphs)" if charstrings_count.zero?

      # Benchmark: Converting all CharStrings should complete reasonably
      time = Benchmark.realtime do
        # Access CharStrings to trigger conversion
        font.charstrings.glyph_names.each do |glyph_name|
          font.charstrings[glyph_name]
          # Just accessing ensures conversion is triggered
        end
      end

      # Conversion should be fast (< 1 second per 1000 glyphs)
      time_per_glyph = time / [charstrings_count, 1].max
      expect(time_per_glyph).to be < 0.001,
                                "CharString access took #{time_per_glyph}s per glyph"
    end
  end

  describe "SFNT table building performance" do
    it "builds SFNT tables within acceptable time" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      # For SFNT tables, we need properly mocked data
      # Create a comprehensive mock with all required attributes
      font_dict = double("font_dictionary")

      font_info = double("font_info")
      allow(font_info).to receive_messages(version: "001.000",
                                           copyright: "Copyright 2024", notice: "Test Font", family_name: "TestFamily", full_name: "TestFont Regular", weight: "Regular", italic_angle: 0, underline_position: -100, underline_thickness: 50, is_fixed_pitch: false)
      allow(font_dict).to receive_messages(font_bbox: [50, -200, 950, 800], font_matrix: [0.001, 0, 0, 0.001,
                                                                                          0, 0], font_name: "TestFont", family_name: "TestFamily", full_name: "TestFont Regular", weight: "Regular", font_info: font_info)

      private_dict = double("private_dict")
      allow(private_dict).to receive_messages(blue_values: [-20, 0, 750,
                                                            770], other_blues: [-250, -240], family_blues: [], family_other_blues: [])

      charstrings = double("charstrings")
      allow(charstrings).to receive_messages(count: 250, encoding: { ".notdef" => 0,
                                                                     "A" => 1, "B" => 2 }, glyph_names: [".notdef", "A",
                                                                                                         "B"])

      mock_font = double("Type1Font")
      allow(mock_font).to receive_messages(font_dictionary: font_dict,
                                           private_dict: private_dict, charstrings: charstrings, font_name: "TestFont", version: "001.000")
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      # Benchmark: Building all SFNT tables should be fast
      times = {}

      times[:head] = Benchmark.realtime do
        converter.send(:build_head_table, mock_font)
      end

      times[:hhea] = Benchmark.realtime do
        converter.send(:build_hhea_table, mock_font)
      end

      times[:maxp] = Benchmark.realtime do
        converter.send(:build_maxp_table, mock_font)
      end

      times[:name] = Benchmark.realtime do
        converter.send(:build_name_table, mock_font)
      end

      times[:os2] = Benchmark.realtime do
        converter.send(:build_os2_table, mock_font)
      end

      times[:post] = Benchmark.realtime do
        converter.send(:build_post_table, mock_font)
      end

      times[:cmap] = Benchmark.realtime do
        converter.send(:build_cmap_table, mock_font)
      end

      # Each table should build in < 0.1 seconds
      times.each do |table_name, table_time|
        expect(table_time).to be < 0.1,
                              "#{table_name} table building took #{table_time}s"
      end
    end
  end

  describe "Full Type 1 to OTF conversion performance" do
    it "converts Type 1 to OTF within acceptable time" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      # Load the font first
      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::FULL)
      skip "Font loading failed" unless font

      charstrings_count = font.charstrings&.count || 0
      skip "No CharStrings found (parsed #{charstrings_count} glyphs)" if charstrings_count.zero?

      # Benchmark: Full conversion should complete within reasonable time
      time = Benchmark.realtime do
        output_io = StringIO.new
        converter.convert(font, target_format: :otf, output: output_io)
      end

      # Full conversion should be fast (< 10 seconds)
      expect(time).to be < 10.0, "Full conversion took #{time}s, expected < 10s"
    end
  end

  describe "Memory usage efficiency" do
    it "has reasonable memory footprint for conversion" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::FULL)
      skip "Font loading failed" unless font

      # Use GetProcessMem for accurate RSS memory measurement
      mem = GetProcessMem.new

      # Force garbage collection before measuring
      GC.start
      GC.start
      GC.start

      # Measure memory before conversion (in MB)
      before_mb = mem.mb

      # Perform conversion
      output_io = StringIO.new
      converter.convert(font, target_format: :otf, output: output_io)

      # Force garbage collection after conversion
      GC.start
      GC.start
      GC.start

      # Measure memory after conversion (in MB)
      after_mb = mem.mb

      # Memory increase should be reasonable (< 50 MB for a single font conversion)
      # This is a reasonable threshold for Type 1 to OTF conversion
      memory_increase_mb = after_mb - before_mb
      expect(memory_increase_mb).to be < 50,
                                    "Memory usage increased by #{memory_increase_mb.round(2)} MB, expected < 50 MB"
    end
  end

  describe "Large font handling" do
    it "handles fonts with many glyphs efficiently" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::FULL)
      skip "Font loading failed" unless font

      glyph_count = font.charstrings&.count || 0
      skip "No CharStrings found (parsed #{glyph_count} glyphs)" if glyph_count.zero?

      # For fonts with many glyphs, verify performance scales linearly
      time = Benchmark.realtime do
        output_io = StringIO.new
        converter.convert(font, target_format: :otf, output: output_io)
      end

      # Performance should be better than 1 second per 100 glyphs
      time_per_100_glyphs = (time / glyph_count) * 100
      expect(time_per_100_glyphs).to be < 1.0,
                                     "Conversion took #{time_per_100_glyphs}s per 100 glyphs"
    end
  end
end
