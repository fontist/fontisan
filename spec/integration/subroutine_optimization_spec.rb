# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Subroutine Optimization Integration" do
  let(:output_dir) { "spec/fixtures/output" }
  let(:ttf_font_path) { "spec/fixtures/fonts/NotoSans-Regular.ttf" }

  before do
    FileUtils.mkdir_p(output_dir)
  end

  after do
    # Clean up generated files
    Dir.glob("#{output_dir}/*").each { |f| FileUtils.rm_f(f) }
  end

  describe "Real-world font optimization" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }

    context "with NotoSans-Regular.ttf" do
      it "successfully converts without optimization" do
        font = Fontisan::FontLoader.load(ttf_font_path)

        expect do
          converter.convert(font, target_format: :otf, optimize_subroutines: false)
        end.not_to raise_error
      end

      it "successfully converts with optimization enabled" do
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = nil
        expect do
          tables = converter.convert(font, target_format: :otf, optimize_subroutines: true)
        end.not_to raise_error

        expect(tables).to be_a(Hash)
        expect(tables["CFF "]).to be_a(String)
      end

      it "generates optimization results with metadata" do
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, {
                                     target_format: :otf,
                                     optimize_subroutines: true,
                                     verbose: true,
                                   })

        optimization = tables.instance_variable_get(:@subroutine_optimization)
        expect(optimization).to be_a(Hash)
        expect(optimization).to include(
          :pattern_count,
          :selected_count,
          :savings,
          :processing_time,
        )
      end

      it "produces valid optimization statistics" do
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, {
                                     target_format: :otf,
                                     optimize_subroutines: true,
                                   })

        optimization = tables.instance_variable_get(:@subroutine_optimization)

        # Pattern count should be non-negative
        expect(optimization[:pattern_count]).to be >= 0
        expect(optimization[:selected_count]).to be >= 0
        expect(optimization[:selected_count]).to be <= optimization[:pattern_count]

        # Savings should be non-negative
        expect(optimization[:savings]).to be >= 0

        # Processing time should be recorded (may be 0 if optimization was skipped)
        expect(optimization[:processing_time]).to be_a(Float)
        expect(optimization[:processing_time]).to be >= 0
      end

      it "includes subroutine details when patterns are found" do
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, {
                                     target_format: :otf,
                                     optimize_subroutines: true,
                                   })

        optimization = tables.instance_variable_get(:@subroutine_optimization)

        if optimization[:selected_count] > 0
          expect(optimization[:subroutines]).to be_an(Array)
          expect(optimization[:subroutines]).not_to be_empty

          # Check subroutine structure
          first_subroutine = optimization[:subroutines].first
          expect(first_subroutine).to include(:commands, :usage_count, :savings)
        end
      end
    end
  end

  describe "Optimization parameters" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }
    let(:font) { Fontisan::FontLoader.load(ttf_font_path) }

    context "with different min_pattern_length values" do
      it "accepts custom min_pattern_length" do
        expect do
          converter.convert(font, {
                              target_format: :otf,
                              optimize_subroutines: true,
                              min_pattern_length: 5,
                            })
        end.not_to raise_error
      end

      it "finds more patterns with lower min_pattern_length" do
        result_low = converter.convert(font, {
                                         target_format: :otf,
                                         optimize_subroutines: true,
                                         min_pattern_length: 5,
                                       })

        result_high = converter.convert(font, {
                                          target_format: :otf,
                                          optimize_subroutines: true,
                                          min_pattern_length: 20,
                                        })

        opt_low = result_low.instance_variable_get(:@subroutine_optimization)
        opt_high = result_high.instance_variable_get(:@subroutine_optimization)

        expect(opt_low[:pattern_count]).to be >= opt_high[:pattern_count]
      end
    end

    context "with different max_subroutines values" do
      it "accepts custom max_subroutines" do
        expect do
          converter.convert(font, {
                              target_format: :otf,
                              optimize_subroutines: true,
                              max_subroutines: 100,
                            })
        end.not_to raise_error
      end

      it "respects max_subroutines limit" do
        result = converter.convert(font, {
                                     target_format: :otf,
                                     optimize_subroutines: true,
                                     max_subroutines: 10,
                                   })

        optimization = result.instance_variable_get(:@subroutine_optimization)
        expect(optimization[:selected_count]).to be <= 10
      end
    end

    context "with optimize_ordering option" do
      it "accepts optimize_ordering parameter" do
        expect do
          converter.convert(font, {
                              target_format: :otf,
                              optimize_subroutines: true,
                              optimize_ordering: false,
                            })
        end.not_to raise_error
      end

      it "processes successfully with ordering disabled" do
        result = converter.convert(font, {
                                     target_format: :otf,
                                     optimize_subroutines: true,
                                     optimize_ordering: false,
                                   })

        optimization = result.instance_variable_get(:@subroutine_optimization)
        expect(optimization).to be_a(Hash)
      end
    end
  end

  describe "Verbose output" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }
    let(:font) { Fontisan::FontLoader.load(ttf_font_path) }

    it "includes detailed information when verbose is enabled" do
      # Capture output
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      begin
        converter.convert(font, {
                            target_format: :otf,
                            optimize_subroutines: true,
                            verbose: true,
                          })
      ensure
        $stdout = original_stdout
      end

      output_text = output.string
      # Should show either optimization results or skip message
      expect(output_text).to match(/Subroutine Optimization Results|optimization skipped/)
    end

    it "does not output details when verbose is disabled" do
      # Capture output
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      begin
        converter.convert(font, {
                            target_format: :otf,
                            optimize_subroutines: true,
                            verbose: false,
                          })
      ensure
        $stdout = original_stdout
      end

      output_text = output.string
      expect(output_text).not_to include("Subroutine Optimization Results")
    end
  end

  describe "Error handling" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }

    it "handles fonts with no CFF data gracefully" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Should not raise error even if optimization finds no patterns
      expect do
        converter.convert(font, {
                            target_format: :otf,
                            optimize_subroutines: true,
                          })
      end.not_to raise_error
    end

    it "continues conversion even if optimization fails" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Mock SubroutineGenerator to raise error
      allow(Fontisan::Optimizers::SubroutineGenerator).to receive(:new).and_raise(StandardError, "Test error")

      # Conversion should still succeed
      result = nil
      expect do
        result = converter.convert(font, {
                                     target_format: :otf,
                                     optimize_subroutines: true,
                                   })
      end.not_to raise_error

      expect(result).to be_a(Hash)
      expect(result["CFF "]).to be_a(String)
    end
  end

  describe "Optimization impact" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }
    let(:font) { Fontisan::FontLoader.load(ttf_font_path) }

    it "produces CFF table regardless of optimization setting" do
      result_without = converter.convert(font, {
                                           target_format: :otf,
                                           optimize_subroutines: false,
                                         })

      result_with = converter.convert(font, {
                                        target_format: :otf,
                                        optimize_subroutines: true,
                                      })

      expect(result_without["CFF "]).to be_a(String)
      expect(result_with["CFF "]).to be_a(String)
    end

    it "maintains table integrity with optimization" do
      result = converter.convert(font, {
                                   target_format: :otf,
                                   optimize_subroutines: true,
                                 })

      # Should have essential tables
      expect(result.keys).to include("CFF ")
      expect(result.keys).not_to include("glyf", "loca")

      # CFF table should be valid binary
      expect(result["CFF "].encoding).to eq(Encoding::BINARY)
      expect(result["CFF "].bytesize).to be > 0
    end
  end

  describe "Performance characteristics" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }
    let(:font) { Fontisan::FontLoader.load(ttf_font_path) }

    it "completes optimization in reasonable time", :slow do
      font = Fontisan::FontLoader.load(ttf_font_path)
      start_time = Time.now

      converter.convert(font,
                        target_format: :otf,
                        optimize_subroutines: true,
                        verbose: true)

      duration = Time.now - start_time

      # Optimization should complete in reasonable time
      # Measured: ~37-41s for 4,515 glyphs on typical hardware
      # Allow margin for slower systems
      expect(duration).to be < 150.0
    end

    it "records accurate processing time" do
      result = converter.convert(font, {
                                   target_format: :otf,
                                   optimize_subroutines: true,
                                 })

      optimization = result.instance_variable_get(:@subroutine_optimization)

      # Processing time should be non-negative (may be 0 if skipped)
      expect(optimization[:processing_time]).to be >= 0
      expect(optimization[:processing_time]).to be < 150.0
    end
  end
end
