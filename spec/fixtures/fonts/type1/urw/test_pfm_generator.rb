#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for PFM generator
# Generates PFM from URW TTF and verifies it can be parsed back

$LOAD_PATH.unshift File.expand_path("../../../../../lib", __dir__)

require "fontisan"
require "fontisan/type1"

ttf_path = File.expand_path("C059-Bold.ttf", __dir__)
pfm_output_path = File.expand_path("C059-Bold-generated.pfm", __dir__)


font = Fontisan::FontLoader.load(ttf_path)

# Use MetricsCalculator for font metrics
metrics = Fontisan::MetricsCalculator.new(font)






# Get OS/2 table for weight info
os2 = font.table("OS/2")
if os2
   if os2.respond_to?(:us_weight_class)
   if os2.respond_to?(:cap_height)
   if os2.respond_to?(:x_height)
end

# Generate PFM

pfm_data = Fontisan::Type1::PFMGenerator.generate(font)

if pfm_data.empty?
  
  exit 1
end



# Write PFM to file
File.binwrite(pfm_output_path, pfm_data)


# Verify by parsing the generated PFM

begin
  parsed_pfm = Fontisan::Type1::PFMParser.parse_file(pfm_output_path)
  
  
  
  
  

  # Show some character widths
  sample_chars = parsed_pfm.character_widths.keys.first(5)
  
  sample_chars.each do |char_idx|
    
  end

  # Check extended metrics
  ext_metrics = parsed_pfm.extended_metrics
  
  ext_metrics.each do |key, value|
    
  end
rescue StandardError => e
  
  
  exit 1
end


