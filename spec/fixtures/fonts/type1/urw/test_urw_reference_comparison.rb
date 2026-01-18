#!/usr/bin/env ruby
# frozen_string_literal: true

# URW Base35 Reference Comparison Test
# Compares Fontisan's TTF -> AFM/PFM generation with URW's reference AFM files

$LOAD_PATH.unshift File.expand_path("../../../../../lib", __dir__)

require "fontisan"
require "fontisan/type1"

class URWReferenceComparison
  def initialize(urw_fonts_dir)
    @urw_fonts_dir = urw_fonts_dir
  end

  def run_all_comparisons
    # Get all TTF files
    ttf_files = Dir[File.join(@urw_fonts_dir, "*.ttf")]

    results = {}
    ttf_files.each do |ttf_path|
      font_name = File.basename(ttf_path, ".ttf")
      results[font_name] = compare_font(ttf_path)
    end

    print_summary(results)
  end

  private

  def compare_font(ttf_path)
    font_name = File.basename(ttf_path, ".ttf")
    afm_path = File.join(@urw_fonts_dir, "#{font_name}.afm")

    result = {
      ttf_to_afm: nil,
      afm_comparison: nil,
      ttf_to_pfm: nil,
    }

    # Load TTF font
    begin
      font = Fontisan::FontLoader.load(ttf_path)
      Fontisan::MetricsCalculator.new(font)

      # Generate AFM from TTF

      generated_afm = Fontisan::Type1::AFMGenerator.generate(font)

      # Parse generated AFM
      parsed_generated_afm = Fontisan::Type1::AFMParser.parse_string(generated_afm)
      result[:ttf_to_afm] = true
    rescue StandardError
      result[:ttf_to_afm] = false
      return result
    end

    # Compare with reference AFM if it exists
    if File.exist?(afm_path)

      begin
        reference_afm_content = File.read(afm_path, encoding: "ISO-8859-1")
        reference_afm = Fontisan::Type1::AFMParser.parse_string(reference_afm_content)

        # Detailed comparison
        comparison = compare_afm_metrics(reference_afm, parsed_generated_afm)
        result[:afm_comparison] = comparison

        # Print differences
        print_afm_differences(comparison)
      rescue StandardError => e
        result[:afm_comparison] = { error: e.message }
      end
    end

    # Generate PFM from TTF

    begin
      generated_pfm = Fontisan::Type1::PFMGenerator.generate(font)
      Fontisan::Type1::PFMParser.parse_string(generated_pfm)
      result[:ttf_to_pfm] = true
    rescue StandardError
      result[:ttf_to_pfm] = false
    end

    result
  end

  def compare_afm_metrics(reference_afm, generated_afm)
    differences = {
      font_name: reference_afm.font_name != generated_afm.font_name,
      full_name: reference_afm.full_name != generated_afm.full_name,
      family_name: reference_afm.family_name != generated_afm.family_name,
      weight: reference_afm.weight != generated_afm.weight,
      italic_angle: nil,
      font_bbox_diff: nil,
      character_widths: {},
      bboxes: {},
    }

    # Compare character widths
    all_glyph_names = (reference_afm.character_widths.keys | generated_afm.character_widths.keys).sort

    all_glyph_names.each do |glyph_name|
      ref_width = reference_afm.character_widths[glyph_name]
      gen_width = generated_afm.character_widths[glyph_name]

      if ref_width != gen_width
        differences[:character_widths][glyph_name] = {
          reference: ref_width,
          generated: gen_width,
          diff: gen_width ? (gen_width - (ref_width || 0)) : nil,
        }
      end

      # Compare bounding boxes
      ref_bbox = reference_afm.character_bboxes[glyph_name]
      gen_bbox = generated_afm.character_bboxes[glyph_name]

      if ref_bbox && gen_bbox && ref_bbox != gen_bbox
        differences[:bboxes][glyph_name] = {
          reference: ref_bbox,
          generated: gen_bbox,
        }
      end
    end

    # Compare font bounding box
    if reference_afm.font_bbox && generated_afm.font_bbox && (reference_afm.font_bbox != generated_afm.font_bbox)
      differences[:font_bbox_diff] = {
        reference: reference_afm.font_bbox,
        generated: generated_afm.font_bbox,
      }
    end

    differences
  end

  def print_afm_differences(comparison)
    if comparison[:error]

      return
    end

    any_differences = false

    if comparison[:font_name]

      any_differences = true
    end

    if comparison[:full_name]

      any_differences = true
    end

    if comparison[:family_name]

      any_differences = true
    end

    if comparison[:weight]

      any_differences = true
    end

    if comparison[:font_bbox_diff]

      any_differences = true
    end

    width_diffs = comparison[:character_widths]
    if !width_diffs.empty?

      # Show first 10 differences
      width_diffs.first(10).each do |glyph_name, diff|
      end

      if width_diffs.count > 10

      end

      any_differences = true
    end

    bbox_diffs = comparison[:bboxes]
    if !bbox_diffs.empty?

      # Show first 5 differences
      bbox_diffs.first(5).each do |glyph_name, diff|
      end

      if bbox_diffs.count > 5

      end

      any_differences = true
    end

    if !any_differences

    end
  end

  def print_summary(results)
    results.count { |_, r| r[:ttf_to_afm] }
    results.count do |_, r|
      r[:afm_comparison] && !r[:afm_comparison][:error]
    end
    results.count do |_, r|
      r[:afm_comparison] && !r[:afm_comparison][:error] &&
        r[:afm_comparison][:character_widths].empty? && !r[:afm_comparison][:font_bbox_diff]
    end
    results.count { |_, r| r[:ttf_to_pfm] }

    # List fonts with differences
    fonts_with_differences = results.select do |_name, r|
      r[:afm_comparison] && !r[:afm_comparison][:error] &&
        (!r[:afm_comparison][:character_widths].empty? || r[:afm_comparison][:font_bbox_diff])
    end

    if !fonts_with_differences.empty?

      fonts_with_differences.each_value do |r|
        r[:afm_comparison][:character_widths].count
        r[:afm_comparison][:font_bbox_diff] ? 1 : 0
      end
    end
  end
end

# Run the comparison test
if __FILE__ == $PROGRAM_NAME
  fixtures_dir = File.expand_path(__dir__)
  urw_fonts_dir = File.join(fixtures_dir, "urw-base35-fonts", "fonts")

  unless Dir.exist?(urw_fonts_dir)

    exit 1
  end

  comparison = URWReferenceComparison.new(urw_fonts_dir)
  comparison.run_all_comparisons
end
