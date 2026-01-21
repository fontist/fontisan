# frozen_string_literal: true

module Fontisan
  # Adobe Type 1 Font support
  #
  # [`Type1`](lib/fontisan/type1.rb) provides parsing and conversion
  # capabilities for Adobe Type 1 fonts in PFB (Printer Font Binary)
  # and PFA (Printer Font ASCII) formats.
  #
  # Type 1 fonts were the standard for digital typography in the 1980s-1990s
  # and are still encountered in legacy systems and design workflows.
  #
  # Key features:
  # - PFB and PFA format parsing
  # - eexec decryption for encrypted font portions
  # - CharString decryption with lenIV handling
  # - Font dictionary parsing (FontInfo, Private dict)
  # - Conversion from TTF/OTF to Type 1 formats
  # - UPM scaling for Type 1 compatibility (1000 UPM)
  # - Multiple encoding support (AdobeStandard, ISOLatin1, Unicode)
  #
  # @example Generate Type 1 formats from TTF
  #   font = Fontisan::FontLoader.load("font.ttf")
  #   result = Fontisan::Type1::Generator.generate(font)
  #   result[:afm]   # => AFM file content
  #   result[:pfm]   # => PFM file content
  #   result[:pfb]   # => PFB file content
  #   result[:inf]   # => INF file content
  #
  # @example Generate with specific options
  #   options = Fontisan::Type1::ConversionOptions.windows_type1
  #   result = Fontisan::Type1::Generator.generate(font, options)
  #
  # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
  module Type1
  end
end

# Parsers
require_relative "type1/pfb_parser"
require_relative "type1/pfa_parser"

# Core components
require_relative "type1/decryptor"
require_relative "type1/font_dictionary"
require_relative "type1/private_dict"
require_relative "type1/charstrings"
require_relative "type1/charstring_converter"
require_relative "type1/cff_to_type1_converter"
require_relative "type1/seac_expander"

# Infrastructure
require_relative "type1/upm_scaler"
require_relative "type1/agl"
require_relative "type1/encodings"
require_relative "type1/conversion_options"

# TTF to Type 1 conversion
require_relative "type1/ttf_to_type1_converter"

# Metrics parsers
require_relative "type1/afm_parser"
require_relative "type1/pfm_parser"

# Metrics generators
require_relative "type1/afm_generator"
require_relative "type1/pfm_generator"

# Type 1 font generators
require_relative "type1/pfa_generator"
require_relative "type1/pfb_generator"
require_relative "type1/inf_generator"

# Unified generator interface
require_relative "type1/generator"
