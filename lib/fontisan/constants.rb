# frozen_string_literal: true

module Fontisan
  # Constants module containing immutable constant definitions for font file operations.
  #
  # This module defines all magic numbers, version identifiers, and file format constants
  # used throughout the fontisan gem. These values are based on the TrueType Collection,
  # TrueType Font, and OpenType Font specifications.
  module Constants
    # TrueType Collection file signature tag.
    # All valid TTC files must begin with this 4-byte tag.
    TTC_TAG = "ttcf"

    # TrueType Collection Version 1.0 identifier.
    # Represents the original TTC format version.
    TTC_VERSION_1 = 0x00010000

    # TrueType Collection Version 2.0 identifier.
    # Represents the extended TTC format with digital signature support.
    TTC_VERSION_2 = 0x00020000

    # SFNT version for TrueType fonts
    SFNT_VERSION_TRUETYPE = 0x00010000

    # SFNT version for OpenType fonts with CFF outlines ('OTTO')
    SFNT_VERSION_OTTO = 0x4F54544F

    # Apple 'true' TrueType signature (alternate to 0x00010000)
    SFNT_VERSION_TRUE = 0x74727965 # 'true' in ASCII

    # dfont resource fork signatures
    DFONT_RESOURCE_HEADER = "\x00\x00\x01\x00"
    SFNT_RESOURCE_TYPE = "sfnt"
    FOND_RESOURCE_TYPE = "FOND"

    # Head table tag identifier.
    # The 'head' table contains global font header information including
    # the checksum adjustment field.
    HEAD_TAG = "head"

    # Hhea table tag identifier (Horizontal Header)
    HHEA_TAG = "hhea"

    # Hmtx table tag identifier (Horizontal Metrics)
    HMTX_TAG = "hmtx"

    # Maxp table tag identifier (Maximum Profile)
    MAXP_TAG = "maxp"

    # Name table tag identifier
    NAME_TAG = "name"

    # OS/2 table tag identifier
    OS2_TAG = "OS/2"

    # Post table tag identifier
    POST_TAG = "post"

    # Cmap table tag identifier
    CMAP_TAG = "cmap"

    # Glyf table tag identifier (TrueType glyph data)
    GLYF_TAG = "glyf"

    # Loca table tag identifier (TrueType glyph index to location)
    LOCA_TAG = "loca"

    # CFF table tag identifier (OpenType CFF glyph data)
    CFF_TAG = "CFF "

    # GSUB table tag identifier (Glyph Substitution)
    GSUB_TAG = "GSUB"

    # GPOS table tag identifier (Glyph Positioning)
    GPOS_TAG = "GPOS"

    # Fvar table tag identifier (Font Variations)
    FVAR_TAG = "fvar"

    # Gvar table tag identifier (Glyph Variations for TrueType)
    GVAR_TAG = "gvar"

    # HVAR table tag identifier (Horizontal Metrics Variations)
    HVAR_TAG = "HVAR"

    # MVAR table tag identifier (Metrics Variations)
    MVAR_TAG = "MVAR"

    # VVAR table tag identifier (Vertical Metrics Variations)
    VVAR_TAG = "VVAR"

    # Cvar table tag identifier (CVT Variations)
    CVAR_TAG = "cvar"

    # CFF2 table tag identifier (CFF version 2 with variations)
    CFF2_TAG = "CFF2"

    # TrueType hinting tables
    # Font Program table (TrueType bytecode executed once at font load)
    FPGM_TAG = "fpgm"

    # Control Value Program table (TrueType bytecode for initialization)
    PREP_TAG = "prep"

    # Control Value Table (metrics used by TrueType hinting)
    CVT_TAG = "cvt "

    # Magic number used for font file checksum adjustment calculation.
    # This constant is used in conjunction with the file checksum to compute
    # the checksumAdjustment value stored in the 'head' table.
    # Formula: checksumAdjustment = CHECKSUM_ADJUSTMENT_MAGIC - file_checksum
    CHECKSUM_ADJUSTMENT_MAGIC = 0xB1B0AFBA

    # Supported TTC version numbers.
    # An array of valid version identifiers for TrueType Collection files.
    SUPPORTED_VERSIONS = [TTC_VERSION_1, TTC_VERSION_2].freeze

    # Table data alignment boundary in bytes.
    # All table data in TTF files must be aligned to 4-byte boundaries,
    # with padding added as necessary.
    TABLE_ALIGNMENT = 4

    # Common font subfamily names for string interning
    #
    # These strings are frozen and reused to reduce memory allocations
    # when parsing fonts with common subfamily names.
    STRING_POOL = {
      "Regular" => "Regular",
      "Bold" => "Bold",
      "Italic" => "Italic",
      "Bold Italic" => "Bold Italic",
      "BoldItalic" => "BoldItalic",
      "Light" => "Light",
      "Medium" => "Medium",
      "Semibold" => "Semibold",
      "SemiBold" => "SemiBold",
      "Black" => "Black",
      "Thin" => "Thin",
      "ExtraLight" => "ExtraLight",
      "Extra Light" => "Extra Light",
      "ExtraBold" => "ExtraBold",
      "Extra Bold" => "Extra Bold",
      "Heavy" => "Heavy",
      "Book" => "Book",
      "Roman" => "Roman",
      "Normal" => "Normal",
      "Oblique" => "Oblique",
      "Light Italic" => "Light Italic",
      "Medium Italic" => "Medium Italic",
      "Semibold Italic" => "Semibold Italic",
      "Bold Oblique" => "Bold Oblique",
    }.freeze

    # Intern a string using the string pool
    #
    # If the string is in the pool, returns the pooled instance.
    # Otherwise, freezes and returns the original string.
    #
    # @param str [String] The string to intern
    # @return [String] The interned string
    def self.intern_string(str)
      STRING_POOL[str] || str.freeze
    end
  end
end
