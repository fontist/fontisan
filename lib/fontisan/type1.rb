# frozen_string_literal: true

# Autoload hub for the Fontisan::Type1 namespace.
#
# Adobe Type 1 Font support — PFB/PFA parsing, eexec decryption,
# CharString decryption, font dictionary parsing, conversion from
# TTF/OTF, UPM scaling, and multiple encoding support.
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

module Fontisan
  module Type1
    autoload :AGL, "fontisan/type1/agl"
    autoload :AFMGenerator, "fontisan/type1/afm_generator"
    autoload :AFMParser, "fontisan/type1/afm_parser"
    autoload :CffToType1Converter, "fontisan/type1/cff_to_type1_converter"
    autoload :CharStringConverter, "fontisan/type1/charstring_converter"
    autoload :CharStrings, "fontisan/type1/charstrings"
    autoload :ConversionOptions, "fontisan/type1/conversion_options"
    autoload :Decryptor, "fontisan/type1/decryptor"
    autoload :Encodings, "fontisan/type1/encodings"
    autoload :FontDictionary, "fontisan/type1/font_dictionary"
    autoload :Generator, "fontisan/type1/generator"
    autoload :INFGenerator, "fontisan/type1/inf_generator"
    autoload :PFAGenerator, "fontisan/type1/pfa_generator"
    autoload :PFAParser, "fontisan/type1/pfa_parser"
    autoload :PFBGenerator, "fontisan/type1/pfb_generator"
    autoload :PFBParser, "fontisan/type1/pfb_parser"
    autoload :PFMGenerator, "fontisan/type1/pfm_generator"
    autoload :PFMParser, "fontisan/type1/pfm_parser"
    autoload :PrivateDict, "fontisan/type1/private_dict"
    autoload :SeacExpander, "fontisan/type1/seac_expander"
    autoload :TTFToType1Converter, "fontisan/type1/ttf_to_type1_converter"
    autoload :UPMScaler, "fontisan/type1/upm_scaler"
  end
end
