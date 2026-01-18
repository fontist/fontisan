# frozen_string_literal: true

require_relative "type1"

module Fontisan
  # Adobe Type 1 Font handler
  #
  # [`Type1Font`](lib/fontisan/type1_font.rb) provides parsing and conversion
  # capabilities for Adobe Type 1 fonts in PFB (Printer Font Binary) and
  # PFA (Printer Font ASCII) formats.
  #
  # Type 1 fonts were the standard for digital typography in the 1980s-1990s
  # and consist of:
  # - Font dictionary with metadata (FontInfo, FontName, Encoding, etc.)
  # - Private dictionary with hinting and spacing information
  # - CharStrings (glyph outline descriptions)
  # - eexec encryption for protection
  #
  # @example Load a PFB file
  #   font = Fontisan::Type1Font.from_file('font.pfb')
  #   puts font.font_name
  #   puts font.version
  #
  # @example Load a PFA file
  #   font = Fontisan::Type1Font.from_file('font.pfa')
  #   puts font.full_name
  #
  # @example Access decrypted font data
  #   font = Fontisan::Type1Font.from_file('font.pfb')
  #   puts font.decrypted_data
  #
  # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
  class Type1Font
    # @return [String, nil] File path if loaded from file
    attr_reader :file_path

    # @return [Symbol] Format type (:pfb or :pfa)
    attr_reader :format

    # @return [String, nil] Decrypted font data
    attr_reader :decrypted_data

    # @return [FontDictionary, nil] Font dictionary
    attr_reader :font_dictionary

    # @return [PrivateDict, nil] Private dictionary
    attr_reader :private_dict

    # @return [CharStrings, nil] CharStrings dictionary
    attr_reader :charstrings

    # Initialize a new Type1Font instance
    #
    # @param data [String] Font file data (binary or text)
    # @param format [Symbol] Format type (:pfb or :pfa, auto-detected if nil)
    # @param file_path [String, nil] Optional file path for reference
    def initialize(data, format: nil, file_path: nil)
      @file_path = file_path
      @format = format || detect_format(data)
      @data = data

      parse_font_data
    end

    # Load Type 1 font from file
    #
    # @param file_path [String] Path to PFB or PFA file
    # @return [Type1Font] Loaded font instance
    # @raise [ArgumentError] If file_path is nil
    # @raise [Fontisan::Error] If file cannot be read or parsed
    #
    # @example Load PFB file
    #   font = Fontisan::Type1Font.from_file('font.pfb')
    #
    # @example Load PFA file
    #   font = Fontisan::Type1Font.from_file('font.pfa')
    def self.from_file(file_path)
      raise ArgumentError, "File path cannot be nil" if file_path.nil?

      unless File.exist?(file_path)
        raise Fontisan::Error, "File not found: #{file_path}"
      end

      # Read file
      data = File.binread(file_path)

      new(data, file_path: file_path)
    end

    # Get clear text portion (before eexec)
    #
    # @return [String] Clear text font dictionary
    def clear_text
      @clear_text ||= ""
    end

    # Get encrypted portion (as hex string for PFA)
    #
    # @return [String] Encrypted portion
    def encrypted_portion
      @encrypted_portion ||= ""
    end

    # Get font name from font dictionary
    #
    # @return [String, nil] Font name or nil if not found
    def font_name
      extract_dictionary_value("/FontName")
    end

    # Get full name from FontInfo
    #
    # @return [String, nil] Full name or nil if not found
    def full_name
      extract_fontinfo_value("FullName")
    end

    # Get family name from FontInfo
    #
    # @return [String, nil] Family name or nil if not found
    def family_name
      extract_fontinfo_value("FamilyName")
    end

    # Get version from FontInfo
    #
    # @return [String, nil] Version or nil if not found
    def version
      extract_fontinfo_value("version")
    end

    # Check if font has been decrypted
    #
    # @return [Boolean] True if font data has been decrypted
    def decrypted?
      !@decrypted_data.nil?
    end

    # Check if font is encrypted
    #
    # @return [Boolean] True if font has eexec encrypted portion
    def encrypted?
      !@encrypted_portion.nil? && !@encrypted_portion.empty?
    end

    # Decrypt the font if not already decrypted
    #
    # @return [String] Decrypted font data
    def decrypt!
      return @decrypted_data if decrypted?

      if @encrypted_portion.nil? || @encrypted_portion.empty?
        @decrypted_data = @clear_text
      else
        encrypted_binary = if @format == :pfa
                             # Convert hex string to binary
                             [@encrypted_portion.gsub(/\s/, "")].pack("H*")
                           else
                             @encrypted_portion
                           end

        @decrypted_data = @clear_text +
          Type1::Decryptor.eexec_decrypt(encrypted_binary)
      end

      @decrypted_data
    end

    # Parse font dictionaries from decrypted data
    #
    # Parses the font dictionary, private dictionary, and CharStrings
    # from the decrypted font data.
    #
    # @return [void]
    def parse_dictionaries!
      decrypt! unless decrypted?

      # Parse font dictionary
      @font_dictionary = Type1::FontDictionary.parse(@decrypted_data)

      # Parse private dictionary
      @private_dict = Type1::PrivateDict.parse(@decrypted_data)

      # Parse CharStrings
      @charstrings = Type1::CharStrings.parse(@decrypted_data, @private_dict)
    end

    # Get font name from font dictionary
    #
    # @return [String, nil] Font name or nil if not found
    def font_name
      return @font_dictionary&.font_name if @font_dictionary

      extract_dictionary_value("/FontName")
    end

    # Get full name from FontInfo
    #
    # @return [String, nil] Full name or nil if not found
    def full_name
      return @font_dictionary&.font_info&.full_name if @font_dictionary

      extract_fontinfo_value("FullName")
    end

    # Get family name from FontInfo
    #
    # @return [String, nil] Family name or nil if not found
    def family_name
      return @font_dictionary&.font_info&.family_name if @font_dictionary

      extract_fontinfo_value("FamilyName")
    end

    # Get version from FontInfo
    #
    # @return [String, nil] Version or nil if not found
    def version
      return @font_dictionary&.font_info&.version if @font_dictionary

      extract_fontinfo_value("version")
    end

    # Get list of glyph names
    #
    # @return [Array<String>] Glyph names
    def glyph_names
      return [] unless @charstrings

      @charstrings.glyph_names
    end

    # Check if dictionaries have been parsed
    #
    # @return [Boolean] True if dictionaries have been parsed
    def parsed_dictionaries?
      !@font_dictionary.nil?
    end

    private

    # Parse font data based on format
    def parse_font_data
      case @format
      when :pfb
        parse_pfb
      when :pfa
        parse_pfa
      else
        raise Fontisan::Error, "Unknown format: #{@format}"
      end
    end

    # Parse PFB format
    def parse_pfb
      parser = Type1::PFBParser.new
      parser.parse(@data)

      # PFB has alternating ASCII and binary parts
      # ASCII parts contain font dictionary
      # Binary parts contain encrypted CharStrings
      @clear_text = parser.ascii_text
      @encrypted_portion = parser.binary_data
    end

    # Parse PFA format
    def parse_pfa
      parser = Type1::PFAParser.new
      parser.parse(@data)

      @clear_text = parser.clear_text
      @encrypted_portion = parser.encrypted_hex
    end

    # Detect format from data
    #
    # @param data [String] Font data
    # @return [Symbol] Detected format (:pfb or :pfa)
    def detect_format(data)
      if Type1::PFBParser.pfb_file?(data)
        :pfb
      elsif Type1::PFAParser.pfa_file?(data)
        :pfa
      else
        raise Fontisan::Error,
              "Cannot detect Type 1 format: not a valid PFB or PFA file"
      end
    end

    # Extract value from font dictionary
    #
    # @param key [String] Dictionary key (e.g., "/FontName")
    # @return [String, nil] Value or nil if not found
    def extract_dictionary_value(key)
      text = decrypted? ? @decrypted_data : @clear_text

      # Look for /FontName /name def pattern
      pattern = /#{Regexp.escape(key)}\s+\/([^\s]+)\s+def/
      match = text.match(pattern)
      return nil unless match

      match[1]
    end

    # Extract value from FontInfo dictionary
    #
    # @param key [String] FontInfo key (e.g., "FullName")
    # @return [String, nil] Value or nil if not found
    def extract_fontinfo_value(key)
      text = decrypted? ? @decrypted_data : @clear_text

      # Look for (FullName) readonly (value) readonly pattern
      # This pattern handles nested parentheses in values
      pattern = /\(#{Regexp.escape(key)}\)\s+readonly\s+(\([^()]*\)|\((?:[^()]*\([^()]*\)[^()]*)*\))\s+readonly/
      match = text.match(pattern)
      return match[1].gsub(/^\(|\)$/, "") if match

      # Look for /FullName (value) def pattern
      pattern = /\/#{Regexp.escape(key)}\s+\(([^)]+)\)\s+def/
      match = text.match(pattern)
      return match[1] if match

      # Look for /FullName (value) readonly readonly pattern
      pattern = /\/#{Regexp.escape(key)}\s+(\([^()]*\)|\((?:[^()]*\([^()]*\)[^()]*)*\))\s+readonly\s+readonly/
      match = text.match(pattern)
      return match[1].gsub(/^\(|\)$/, "") if match

      nil
    end
  end
end
