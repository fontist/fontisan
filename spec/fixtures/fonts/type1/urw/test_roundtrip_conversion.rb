#!/usr/bin/env ruby
# frozen_string_literal: true

# Round-trip conversion comparison test suite
# Tests TTF -> AFM/PFM -> Parse -> Compare with original TTF metrics

$LOAD_PATH.unshift File.expand_path("../../../../../lib", __dir__)

require "fontisan"
require "fontisan/type1"

class RoundTripComparisonTest
  def initialize(ttf_path)
    @ttf_path = ttf_path
    @font = nil
    @metrics = nil
    @afm_output_path = nil
    @pfm_output_path = nil
  end

  def run
    load_font
    return false unless @font

    test_afm_roundtrip
    test_pfm_roundtrip

    true
  end

  private

  def load_font
    @font = Fontisan::FontLoader.load(@ttf_path)
    @metrics = Fontisan::MetricsCalculator.new(@font)
  rescue StandardError
    false
  end

  def test_afm_roundtrip
    @afm_output_path = @ttf_path.sub(".ttf", "-generated.afm")

    # Generate AFM
    afm_data = Fontisan::Type1::AFMGenerator.generate(@font)
    if afm_data.empty?

      return
    end

    File.write(@afm_output_path, afm_data)

    # Parse AFM
    parsed_afm = Fontisan::Type1::AFMParser.parse_file(@afm_output_path)

    # Compare metrics
    compare_afm_metrics(parsed_afm)
  rescue StandardError
  end

  def test_pfm_roundtrip
    @pfm_output_path = @ttf_path.sub(".ttf", "-generated.pfm")

    # Generate PFM
    pfm_data = Fontisan::Type1::PFMGenerator.generate(@font)
    if pfm_data.empty?

      return
    end

    File.binwrite(@pfm_output_path, pfm_data)

    # Parse PFM
    parsed_pfm = Fontisan::Type1::PFMParser.parse_file(@pfm_output_path)

    # Compare metrics
    compare_pfm_metrics(parsed_pfm)
  rescue StandardError
  end

  def compare_afm_metrics(parsed_afm)
    # Compare basic metrics

    # Check some character widths using glyph names
    # AFM uses glyph names, not character codes
    sample_glyphs = [
      { name: "space", code: 32 },
      { name: "A", code: 65 },
      { name: "B", code: 66 },
      { name: "C", code: 67 },
    ]

    sample_glyphs.each do |glyph|
      cmap = @font.table(Fontisan::Constants::CMAP_TAG)
      next unless cmap

      mappings = cmap.respond_to?(:unicode_mappings) ? cmap.unicode_mappings : {}
      glyph_id = mappings[glyph[:code]]
      next unless glyph_id

      original_width = @metrics.glyph_width(glyph_id)
      afm_width = parsed_afm.width(glyph[:name])

      if afm_width
        check_match("Char #{glyph[:code]}", afm_width, original_width,
                    tolerance: 1)
      end
    end
  end

  def compare_pfm_metrics(parsed_pfm)
    # Compare extended metrics
    parsed_pfm.extended_metrics

    # Check some character widths
    sample_glyphs = [32, 65, 66, 67] # Space, A, B, C

    sample_glyphs.each do |char_code|
      cmap = @font.table(Fontisan::Constants::CMAP_TAG)
      next unless cmap

      mappings = cmap.respond_to?(:unicode_mappings) ? cmap.unicode_mappings : {}
      glyph_id = mappings[char_code]
      next unless glyph_id

      original_width = @metrics.glyph_width(glyph_id)
      pfm_width = parsed_pfm.width(char_code)

      check_match("Char #{char_code}", pfm_width, original_width, tolerance: 1)
    end
  end

  def check_match(_name, generated, original, tolerance: 0)
    diff = (generated - original).abs
    if diff <= tolerance

    end
  end
end

# Run tests on URW fonts
if __FILE__ == $PROGRAM_NAME
  fixtures_dir = File.expand_path(__dir__)

  # Test URW Base35 fonts
  urw_fonts_dir = File.join(fixtures_dir, "urw-base35-fonts", "fonts")
  ttfs = if Dir.exist?(urw_fonts_dir)
           Dir[File.join(urw_fonts_dir, "*.ttf")]
         else
           []
         end

  if ttfs.empty?

    exit 1
  end

  ttfs.map do |ttf_path|
    test = RoundTripComparisonTest.new(ttf_path)
    test.run
  end

end
