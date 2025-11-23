# frozen_string_literal: true

require "spec_helper"
require "fontisan"

RSpec.describe "Round-Trip Validation" do
  let(:ttf_font_path) do
    File.join(File.dirname(__FILE__), "..", "fixtures", "fonts",
              "NotoSans-Regular.ttf")
  end

  let(:converter) { Fontisan::Converters::OutlineConverter.new }

  describe "TTF → OTF → Outline Validation" do
    context "without optimization" do
      it "produces identical glyph outlines" do
        # Load original font
        font = Fontisan::FontLoader.load(ttf_font_path)

        # Extract original outlines
        original_outlines = converter.extract_ttf_outlines(font)

        # Convert to OTF without optimization
        tables = converter.convert(font,
                                   target_format: :otf,
                                   optimize_subroutines: false,
                                   stack_aware: true)

        # Create temporary font with new tables to extract CFF outlines
        temp_font = create_temp_font(font, tables)

        # Extract optimized outlines
        cff_outlines = converter.extract_cff_outlines(temp_font)

        # Compare outline counts
        expect(cff_outlines.length).to eq(original_outlines.length)

        # Compare each outline's commands
        original_outlines.each_with_index do |orig, idx|
          cff = cff_outlines[idx]

          # Compare outline properties
          expect(cff.glyph_id).to eq(orig.glyph_id)
          expect(cff.empty?).to eq(orig.empty?)

          # Skip empty glyphs
          next if orig.empty?

          # Compare bounding boxes (allow tolerance for rounding during conversion)
          # Quadratic to cubic conversion and coordinate rounding can cause small differences
          expect(cff.bbox[:x_min]).to be_within(2).of(orig.bbox[:x_min])
          expect(cff.bbox[:y_min]).to be_within(2).of(orig.bbox[:y_min])
          expect(cff.bbox[:x_max]).to be_within(2).of(orig.bbox[:x_max])
          expect(cff.bbox[:y_max]).to be_within(2).of(orig.bbox[:y_max])

          # Filter out close_path commands for comparison
          # CFF doesn't have explicit closepath - contours are implicitly closed
          # So we compare the path commands without closepath
          orig_path_commands = orig.commands.reject { |c| c[:type] == :close_path }
          cff_path_commands = cff.commands.reject { |c| c[:type] == :close_path }

          # Compare command counts (excluding closepath)
          expect(cff_path_commands.length).to eq(orig_path_commands.length),
                                              "Glyph #{idx}: path command count mismatch"

          # Compare each command (with tolerance for coordinate differences)
          # Note: TTF uses quadratic curves (:quad_to) while CFF uses cubic (:curve_to)
          # After TTF→CFF conversion, quadratics are elevated to cubics (exact conversion)
          # We compare commands excluding closepath since CFF doesn't have explicit closepath
          cff_path_commands.each_with_index do |cff_cmd, cmd_idx|
            orig_cmd = orig_path_commands[cmd_idx]

            # Handle curve type differences between TTF (quadratic) and CFF (cubic)
            case [orig_cmd[:type], cff_cmd[:type]]
            when %i[move_to move_to], %i[line_to line_to], %i[close_path close_path]
              # Direct match - compare coordinates
              if orig_cmd[:type] == :close_path
                # close_path has no coordinates
              else
                expect(cff_cmd[:x]).to be_within(2).of(orig_cmd[:x])
                expect(cff_cmd[:y]).to be_within(2).of(orig_cmd[:y])
              end
            when %i[quad_to curve_to]
              # TTF quadratic elevated to CFF cubic
              # Compare end points (start point is from previous command)
              expect(cff_cmd[:x]).to be_within(2).of(orig_cmd[:x])
              expect(cff_cmd[:y]).to be_within(2).of(orig_cmd[:y])
              # Note: Control points won't match exactly due to degree elevation
              # but the curve shape should be equivalent
            when %i[curve_to curve_to]
              # Both cubic - direct comparison
              expect(cff_cmd[:x1]).to be_within(2).of(orig_cmd[:x1])
              expect(cff_cmd[:y1]).to be_within(2).of(orig_cmd[:y1])
              expect(cff_cmd[:x2]).to be_within(2).of(orig_cmd[:x2])
              expect(cff_cmd[:y2]).to be_within(2).of(orig_cmd[:y2])
              expect(cff_cmd[:x]).to be_within(2).of(orig_cmd[:x])
              expect(cff_cmd[:y]).to be_within(2).of(orig_cmd[:y])
            else
              # Unexpected mismatch
              expect(cff_cmd[:type]).to eq(orig_cmd[:type]),
                                        "Unexpected curve type mismatch at command #{cmd_idx}: " \
                                        "#{orig_cmd[:type]} → #{cff_cmd[:type]}"
            end
          end
        end
      end
    end

    context "with optimization" do
      it "produces identical glyph outlines after subroutine optimization",
         :slow do
        # Load original font
        font = Fontisan::FontLoader.load(ttf_font_path)

        # Extract original outlines
        original_outlines = converter.extract_ttf_outlines(font)

        # Convert to OTF with optimization
        tables = converter.convert(font,
                                   target_format: :otf,
                                   optimize_subroutines: true,
                                   stack_aware: true,
                                   min_pattern_length: 10,
                                   max_subroutines: 1000)

        # Create temporary font with new tables to extract CFF outlines
        temp_font = create_temp_font(font, tables)

        # Extract optimized outlines (with subroutine resolution)
        cff_outlines = converter.extract_cff_outlines(temp_font)

        # Compare outline counts
        expect(cff_outlines.length).to eq(original_outlines.length)

        # Sample validation: check first 100 glyphs and a random sample
        sample_indices = [*0..99] + (100...original_outlines.length).to_a.sample(100)
        sample_indices.each do |idx|
          orig = original_outlines[idx]
          cff = cff_outlines[idx]

          # Compare outline properties
          expect(cff.glyph_id).to eq(orig.glyph_id)
          expect(cff.empty?).to eq(orig.empty?)

          # Skip empty glyphs
          next if orig.empty?

          # Compare bounding boxes (allow tolerance for rounding during conversion)
          # Quadratic to cubic conversion and coordinate rounding can cause small differences
          expect(cff.bbox[:x_min]).to be_within(2).of(orig.bbox[:x_min])
          expect(cff.bbox[:y_min]).to be_within(2).of(orig.bbox[:y_min])
          expect(cff.bbox[:x_max]).to be_within(2).of(orig.bbox[:x_max])
          expect(cff.bbox[:y_max]).to be_within(2).of(orig.bbox[:y_max])

          # Filter out close_path commands for comparison
          # CFF doesn't have explicit closepath - contours are implicitly closed
          orig_path_commands = orig.commands.reject { |c| c[:type] == :close_path }
          cff_path_commands = cff.commands.reject { |c| c[:type] == :close_path }

          # Compare command counts (excluding closepath)
          expect(cff_path_commands.length).to eq(orig_path_commands.length),
                                              "Glyph #{idx}: path command count mismatch"

          # Compare first and last few commands in detail
          # Note: TTF uses quadratic curves (:quad_to) while CFF uses cubic (:curve_to)
          # We compare commands excluding closepath since CFF doesn't have explicit closepath
          [0, 1, 2, -3, -2, -1].each do |cmd_idx|
            next if cmd_idx.abs >= cff_path_commands.length

            cff_cmd = cff_path_commands[cmd_idx]
            orig_cmd = orig_path_commands[cmd_idx]

            # Handle curve type differences between TTF (quadratic) and CFF (cubic)
            case [orig_cmd[:type], cff_cmd[:type]]
            when %i[move_to move_to], %i[line_to line_to], %i[close_path close_path]
              # Direct match - compare coordinates
              if orig_cmd[:type] == :close_path
                # close_path has no coordinates
              else
                expect(cff_cmd[:x]).to be_within(2).of(orig_cmd[:x])
                expect(cff_cmd[:y]).to be_within(2).of(orig_cmd[:y])
              end
            when %i[quad_to curve_to]
              # TTF quadratic elevated to CFF cubic
              # Compare end points (control points won't match due to degree elevation)
              expect(cff_cmd[:x]).to be_within(2).of(orig_cmd[:x])
              expect(cff_cmd[:y]).to be_within(2).of(orig_cmd[:y])
            when %i[curve_to curve_to]
              # Both cubic - direct comparison
              expect(cff_cmd[:x1]).to be_within(2).of(orig_cmd[:x1])
              expect(cff_cmd[:y1]).to be_within(2).of(orig_cmd[:y1])
              expect(cff_cmd[:x2]).to be_within(2).of(orig_cmd[:x2])
              expect(cff_cmd[:y2]).to be_within(2).of(orig_cmd[:y2])
              expect(cff_cmd[:x]).to be_within(2).of(orig_cmd[:x])
              expect(cff_cmd[:y]).to be_within(2).of(orig_cmd[:y])
            else
              # Unexpected mismatch
              expect(cff_cmd[:type]).to eq(orig_cmd[:type]),
                                        "Unexpected curve type mismatch at command #{cmd_idx}"
            end
          end
        end
      end

      it "successfully resolves subroutine calls", :slow do
        # Load font
        font = Fontisan::FontLoader.load(ttf_font_path)

        # Convert with optimization
        tables = converter.convert(font,
                                   target_format: :otf,
                                   optimize_subroutines: true,
                                   verbose: false)

        # Verify optimization occurred
        opt_result = tables.instance_variable_get(:@subroutine_optimization)
        expect(opt_result).not_to be_nil
        expect(opt_result[:local_subrs]).not_to be_empty
        expect(opt_result[:selected_count]).to be > 0

        # Create temporary font
        temp_font = create_temp_font(font, tables)

        # Parse CFF table
        cff = temp_font.table("CFF ")
        expect(cff).not_to be_nil

        # Verify Local Subrs INDEX is present
        local_subrs = cff.local_subrs(0)
        expect(local_subrs).not_to be_nil
        expect(local_subrs.count).to eq(opt_result[:local_subrs].length)

        # Test that we can extract CharStrings successfully
        # This implicitly tests subroutine resolution since extract_cff_outlines
        # calls charstring_for_glyph which executes the CharString interpreter
        outlines = converter.extract_cff_outlines(temp_font)
        expect(outlines).not_to be_empty
        expect(outlines.length).to eq(cff.glyph_count)

        # Verify some glyphs have non-empty outlines
        non_empty_count = outlines.count { |o| !o.empty? }
        expect(non_empty_count).to be > 100
      end
    end
  end

  # Helper method to create a temporary font object with new tables
  def create_temp_font(_source_font, tables)
    temp_font = Object.new

    temp_font.define_singleton_method(:table) do |tag|
      return nil unless tables[tag]

      case tag
      when "CFF ", "CFF2"
        cff = Fontisan::Tables::Cff.new
        cff.parse!(tables[tag])
        cff
      when "head"
        head = Fontisan::Tables::Head.new
        head.parse!(tables[tag])
        head
      when "maxp"
        maxp = Fontisan::Tables::Maxp.new
        maxp.parse!(tables[tag])
        maxp
      else
        # Return raw data for other tables
        tables[tag]
      end
    end

    temp_font.define_singleton_method(:table_data) do
      tables
    end

    temp_font.define_singleton_method(:has_table?) do |tag|
      tables.key?(tag)
    end

    temp_font
  end
end
