# frozen_string_literal: true

require "stringio"
require_relative "../../binary/base_record"

module Fontisan
  module Tables
    class Cff
      # CFF Charset structure
      #
      # Charset maps glyph IDs (GIDs) to glyph names via String IDs (SIDs).
      # GID 0 is always `.notdef` and is not included in the Charset data.
      #
      # Three formats:
      # - Format 0: Array of SIDs, one per glyph (except .notdef)
      # - Format 1: Ranges with 8-bit nLeft counts
      # - Format 2: Ranges with 16-bit nLeft counts
      #
      # Predefined charsets:
      # - 0: ISOAdobe charset (SIDs 0-228)
      # - 1: Expert charset
      # - 2: Expert Subset charset
      #
      # Reference: CFF specification section 13 "Charsets"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Reading a Charset
      #   charset = Fontisan::Tables::Cff::Charset.new(
      #     data, num_glyphs, cff_table
      #   )
      #   puts charset.glyph_name(5)  # => "A"
      #   puts charset.glyph_id("A")  # => 5
      class Charset
        # Format identifiers
        FORMATS = {
          0 => :array,
          1 => :range_8,
          2 => :range_16,
        }.freeze

        # Predefined charset identifiers
        PREDEFINED = {
          0 => :iso_adobe,
          1 => :expert,
          2 => :expert_subset,
        }.freeze

        # @return [Integer] Charset format (0, 1, or 2)
        attr_reader :format_type

        # @return [Array<String>] Glyph names indexed by GID
        attr_reader :glyph_names

        # Initialize a Charset
        #
        # @param data [String, Integer] Binary data or predefined charset ID
        # @param num_glyphs [Integer] Number of glyphs in the font
        # @param cff_table [Cff] Parent CFF table for string lookup
        def initialize(data, num_glyphs, cff_table)
          @num_glyphs = num_glyphs
          @cff_table = cff_table
          @glyph_names = [".notdef"] # GID 0 is always .notdef
          @glyph_name_to_id = { ".notdef" => 0 }

          if data.is_a?(Integer) && PREDEFINED.key?(data)
            load_predefined_charset(data)
          else
            @data = data
            parse!
          end
        end

        # Get glyph name for a GID
        #
        # @param gid [Integer] Glyph ID
        # @return [String, nil] Glyph name or nil if invalid GID
        def glyph_name(gid)
          return nil if gid.negative? || gid >= @glyph_names.size

          @glyph_names[gid]
        end

        # Get GID for a glyph name
        #
        # @param name [String] Glyph name
        # @return [Integer, nil] Glyph ID or nil if not found
        def glyph_id(name)
          @glyph_name_to_id[name]
        end

        # Get the format symbol
        #
        # @return [Symbol] Format identifier (:array, :range_8, :range_16, or
        #   :predefined)
        def format
          @format_type ? FORMATS[@format_type] : :predefined
        end

        private

        # Parse the Charset from binary data
        def parse!
          io = StringIO.new(@data)
          @format_type = read_uint8(io)

          case @format_type
          when 0
            parse_format_0(io)
          when 1
            parse_format_1(io)
          when 2
            parse_format_2(io)
          else
            raise CorruptedTableError,
                  "Invalid Charset format: #{@format_type}"
          end

          build_name_to_id_map
        rescue StandardError => e
          raise CorruptedTableError,
                "Failed to parse Charset: #{e.message}"
        end

        # Parse Format 0: Array of SIDs
        #
        # Format 0 directly lists SIDs for each glyph (except .notdef at GID 0)
        #
        # @param io [StringIO] Input stream positioned after format byte
        def parse_format_0(io)
          # Read one SID per glyph (num_glyphs - 1, excluding .notdef)
          (@num_glyphs - 1).times do
            sid = read_uint16(io)
            glyph_name = sid_to_glyph_name(sid)
            @glyph_names << glyph_name
          end
        end

        # Parse Format 1: Ranges with 8-bit counts
        #
        # Format 1 uses ranges: first SID, nLeft (number of consecutive SIDs)
        #
        # @param io [StringIO] Input stream positioned after format byte
        def parse_format_1(io)
          glyph_count = 1 # Start at 1 (we already have .notdef at 0)

          while glyph_count < @num_glyphs
            first_sid = read_uint16(io)
            n_left = read_uint8(io)

            # Add glyphs for this range
            (n_left + 1).times do |i|
              sid = first_sid + i
              glyph_name = sid_to_glyph_name(sid)
              @glyph_names << glyph_name
              glyph_count += 1
              break if glyph_count >= @num_glyphs
            end
          end
        end

        # Parse Format 2: Ranges with 16-bit counts
        #
        # Format 2 is like Format 1 but with 16-bit nLeft values
        #
        # @param io [StringIO] Input stream positioned after format byte
        def parse_format_2(io)
          glyph_count = 1 # Start at 1 (we already have .notdef at 0)

          while glyph_count < @num_glyphs
            first_sid = read_uint16(io)
            n_left = read_uint16(io)

            # Add glyphs for this range
            (n_left + 1).times do |i|
              sid = first_sid + i
              glyph_name = sid_to_glyph_name(sid)
              @glyph_names << glyph_name
              glyph_count += 1
              break if glyph_count >= @num_glyphs
            end
          end
        end

        # Load a predefined charset
        #
        # @param charset_id [Integer] Predefined charset ID (0, 1, or 2)
        def load_predefined_charset(charset_id)
          @format_type = nil # Predefined charsets don't have a format

          case charset_id
          when 0
            load_iso_adobe_charset
          when 1
            load_expert_charset
          when 2
            load_expert_subset_charset
          end

          build_name_to_id_map
        end

        # Load ISOAdobe charset (SIDs 0-228)
        #
        # This is the standard charset containing common Latin glyphs
        def load_iso_adobe_charset
          # ISOAdobe charset contains SIDs 0-228
          # For a full implementation, we would need all 229 glyphs
          # Here we generate them from SIDs
          (@num_glyphs - 1).times do |i|
            sid = i + 1 # Skip 0 (.notdef)
            break if sid > 228

            @glyph_names << sid_to_glyph_name(sid)
          end
        end

        # Load Expert charset
        #
        # This is a special charset for expert fonts with additional glyphs
        def load_expert_charset
          # Expert charset contains specific SIDs for expert glyphs
          # This is a placeholder - a full implementation would include the
          # complete expert charset SID list from the CFF specification
          (@num_glyphs - 1).times do |i|
            @glyph_names << sid_to_glyph_name(i + 1)
          end
        end

        # Load Expert Subset charset
        #
        # This is a subset of the Expert charset
        def load_expert_subset_charset
          # Expert Subset contains a subset of expert glyphs
          # This is a placeholder - a full implementation would include the
          # complete expert subset charset SID list from the CFF specification
          (@num_glyphs - 1).times do |i|
            @glyph_names << sid_to_glyph_name(i + 1)
          end
        end

        # Convert SID to glyph name
        #
        # @param sid [Integer] String ID
        # @return [String] Glyph name
        def sid_to_glyph_name(sid)
          @cff_table.string_for_sid(sid) || ".notdef"
        end

        # Build the name-to-ID lookup map
        def build_name_to_id_map
          @glyph_names.each_with_index do |name, gid|
            @glyph_name_to_id[name] = gid
          end
        end

        # Read an unsigned 8-bit integer
        #
        # @param io [StringIO] Input stream
        # @return [Integer] The value
        def read_uint8(io)
          byte = io.read(1)
          raise CorruptedTableError, "Unexpected end of Charset data" if
            byte.nil?

          byte.unpack1("C")
        end

        # Read an unsigned 16-bit integer (big-endian)
        #
        # @param io [StringIO] Input stream
        # @return [Integer] The value
        def read_uint16(io)
          bytes = io.read(2)
          raise CorruptedTableError, "Unexpected end of Charset data" if
            bytes.nil? || bytes.bytesize < 2

          bytes.unpack1("n") # Big-endian unsigned 16-bit
        end
      end
    end
  end
end
