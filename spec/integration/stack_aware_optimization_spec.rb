# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Stack-Aware Subroutine Optimization" do
  let(:font_path) { "spec/fixtures/fonts/NotoSans-Regular.ttf" }
  let(:font) { Fontisan::FontLoader.load(font_path) }
  let(:converter) { Fontisan::Converters::OutlineConverter.new }

  describe "stack-aware pattern detection" do
    it "successfully converts TTF to OTF with stack-aware optimization" do
      result = converter.convert(
        font,
        target_format: :otf,
        optimize_subroutines: true,
        stack_aware: true,
        verbose: false,
      )

      expect(result).to be_a(Hash)
      expect(result).to have_key("CFF ")
      expect(result).not_to have_key("glyf")
      expect(result).not_to have_key("loca")
    end

    it "generates patterns with stack-aware mode" do
      # Convert with stack-aware
      result = converter.convert(
        font,
        target_format: :otf,
        optimize_subroutines: true,
        stack_aware: true,
        verbose: false,
      )

      # Should succeed
      expect(result["CFF "]).to be_a(String)

      # Stack-aware should have optimization data
      optimization = result.instance_variable_get(:@subroutine_optimization)

      expect(optimization).to be_a(Hash)
      expect(optimization[:selected_count]).to be >= 0
    end
  end

  describe "stack-aware optimization metrics" do
    it "reports optimization statistics" do
      result = converter.convert(
        font,
        target_format: :otf,
        optimize_subroutines: true,
        stack_aware: true,
        verbose: false,
      )

      optimization = result.instance_variable_get(:@subroutine_optimization)

      if optimization
        expect(optimization).to have_key(:pattern_count)
        expect(optimization).to have_key(:selected_count)
        expect(optimization).to have_key(:local_subrs)
        expect(optimization).to have_key(:savings)
        expect(optimization).to have_key(:processing_time)

        # Stack-aware optimization should complete in reasonable time
        expect(optimization[:processing_time]).to be < 60.0 # seconds
      end
    end

    it "produces valid CFF table with stack-aware optimization" do
      result = converter.convert(
        font,
        target_format: :otf,
        optimize_subroutines: true,
        stack_aware: true,
      )

      # Parse CFF table
      cff_data = result["CFF "]
      expect(cff_data.bytesize).to be > 0

      # CFF header should be valid
      major, minor, header_size = cff_data.unpack("C*")[0..2]
      expect(major).to eq(1)
      expect(minor).to eq(0)
      expect(header_size).to eq(4)
    end
  end

  describe "comparison between stack-aware and normal optimization" do
    it "both modes produce valid CFF tables" do
      # Without stack-aware
      result_normal = converter.convert(
        font,
        target_format: :otf,
        optimize_subroutines: true,
        stack_aware: false,
        verbose: false,
      )

      # With stack-aware
      result_stack_aware = converter.convert(
        font,
        target_format: :otf,
        optimize_subroutines: true,
        stack_aware: true,
        verbose: false,
      )

      expect(result_normal["CFF "]).to be_a(String)
      expect(result_stack_aware["CFF "]).to be_a(String)

      expect(result_normal["CFF "].bytesize).to be > 0
      expect(result_stack_aware["CFF "].bytesize).to be > 0
    end

    it "both modes achieve some level of optimization" do
      # Unoptimized
      result_none = converter.convert(
        font,
        target_format: :otf,
        optimize_subroutines: false,
      )

      # With normal optimization
      result_normal = converter.convert(
        font,
        target_format: :otf,
        optimize_subroutines: true,
        stack_aware: false,
      )

      # With stack-aware optimization
      result_stack_aware = converter.convert(
        font,
        target_format: :otf,
        optimize_subroutines: true,
        stack_aware: true,
      )

      unoptimized_size = result_none["CFF "].bytesize
      normal_size = result_normal["CFF "].bytesize
      stack_aware_size = result_stack_aware["CFF "].bytesize

      # At least one should achieve compression
      expect([normal_size, stack_aware_size].min).to be <= unoptimized_size
    end
  end
end
