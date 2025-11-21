# frozen_string_literal: true

module Fontisan
  module Subset
    # Table-specific subsetting strategies
    #
    # This class provides methods for subsetting individual font tables according
    # to the glyph mapping. Each table type has different subsetting requirements:
    #
    # - maxp: Update glyph count
    # - hhea: Update horizontal metrics count
    # - hmtx: Subset horizontal metrics
    # - glyf: Subset glyph data and remap component references
    # - loca: Rebuild glyph location index
    # - cmap: Remap character to glyph mappings
    # - post: Optionally drop glyph names
    # - name: Pass through (no subsetting needed)
    # - head: Update checksum adjustment (handled by FontWriter)
    # - OS/2: Optionally prune Unicode ranges
    #
    # The subsetting process preserves font validity by updating all references
    # and recalculating offsets and checksums.
    #
    # @example Subset a single table
    #   subsetter = TableSubsetter.new(font, mapping, options)
    #   maxp_data = subsetter.subset_maxp(maxp_table)
    #
    # @example Subset all tables
    #   subsetter = TableSubsetter.new(font, mapping, options)
    #   subset_tables = {}
    #   profile_tables.each do |tag|
    #     table = font.table(tag)
    #     subset_tables[tag] = subsetter.subset_table(tag, table) if table
    #   end
    class TableSubsetter
      # Font instance being subset
      # @return [TrueTypeFont, OpenTypeFont]
      attr_reader :font

      # Glyph ID mapping (old GID → new GID)
      # @return [GlyphMapping]
      attr_reader :mapping

      # Subsetting options
      # @return [Options]
      attr_reader :options

      # Initialize table subsetter
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to subset
      # @param mapping [GlyphMapping] Glyph ID mapping
      # @param options [Options] Subsetting options
      def initialize(font, mapping, options)
        @font = font
        @mapping = mapping
        @options = options
        @glyf_data = nil
        @loca_offsets = nil
      end

      # Subset a table by tag
      #
      # Delegates to table-specific subsetting methods. Unknown tables
      # are passed through unchanged.
      #
      # @param tag [String] Table tag (e.g., "glyf", "hmtx")
      # @param table [Object] Parsed table object
      # @return [String] Binary data of subset table
      def subset_table(tag, table)
        case tag
        when "maxp"
          subset_maxp(table)
        when "hhea"
          subset_hhea(table)
        when "hmtx"
          subset_hmtx(table)
        when "loca"
          subset_loca(table)
        when "glyf"
          subset_glyf(table)
        when "cmap"
          subset_cmap(table)
        when "post"
          subset_post(table)
        when "name"
          subset_name(table)
        when "head"
          subset_head(table)
        when "OS/2"
          subset_os2(table)
        else
          # Unknown tables pass through unchanged
          font.table_data[tag]
        end
      end

      # Subset maxp table (update numGlyphs)
      #
      # Updates the numGlyphs field to reflect the number of glyphs in
      # the subset font.
      #
      # @param table [Maxp] Parsed maxp table
      # @return [String] Binary data of subset maxp table
      def subset_maxp(table)
        data = table.to_binary_s.dup

        # Update numGlyphs field (at offset 4, uint16)
        data[4, 2] = [mapping.size].pack("n")

        data
      end

      # Subset hhea table (update numberOfHMetrics)
      #
      # Updates the numberOfHMetrics field to reflect the number of
      # horizontal metrics in the subset font.
      #
      # @param table [Hhea] Parsed hhea table
      # @param hmtx [Hmtx, nil] Optional parsed hmtx table (for calculating metrics)
      # @return [String] Binary data of subset hhea table
      def subset_hhea(table, hmtx = nil)
        data = table.to_binary_s.dup

        # Calculate new numberOfHMetrics
        new_num_h_metrics = if hmtx && hmtx.h_metrics
                             hmtx.h_metrics.size
                           else
                             calculate_number_of_h_metrics
                           end

        # Update numberOfHMetrics field (at offset 34, uint16)
        data[34, 2] = [new_num_h_metrics].pack("n")

        data
      end

      # Subset hmtx table (subset horizontal metrics)
      #
      # Builds new hmtx table with metrics for subset glyphs only,
      # preserving the order of the glyph mapping.
      #
      # @param table [Hmtx] Parsed hmtx table
      # @return [String] Binary data of subset hmtx table
      def subset_hmtx(table)
        # Ensure hmtx is parsed
        unless table.parsed?
          hhea = font.table("hhea")
          maxp = font.table("maxp")
          table.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)
        end

        # Build new hmtx data
        data = String.new(encoding: Encoding::BINARY)

        mapping.each do |old_id, _new_id|
          metric = table.metric_for(old_id)
          next unless metric

          data << [metric[:advance_width]].pack("n")
          data << [metric[:lsb]].pack("n")
        end

        data
      end

      # Subset glyf table (subset glyph data)
      #
      # Extracts glyph data for subset glyphs and remaps component
      # references in compound glyphs. Also builds loca offsets.
      #
      # @param table [Glyf] Parsed glyf table
      # @return [String] Binary data of subset glyf table
      def subset_glyf(table)
        # Build glyf and loca together
        build_glyf_and_loca(table)
        @glyf_data
      end

      # Subset loca table (rebuild glyph location index)
      #
      # Builds new loca table based on subset glyph offsets. Must be
      # called after subset_glyf.
      #
      # @param table [Loca] Parsed loca table
      # @return [String] Binary data of subset loca table
      def subset_loca(_table)
        # Build glyf and loca together if not already done
        glyf = font.table("glyf")
        build_glyf_and_loca(glyf) unless @loca_offsets

        head = font.table("head")
        format = head.index_to_loc_format

        data = String.new(encoding: Encoding::BINARY)

        if format.zero?
          # Short format: offsets / 2 as uint16
          @loca_offsets.each do |offset|
            data << [offset / 2].pack("n")
          end
        else
          # Long format: offsets as uint32
          @loca_offsets.each do |offset|
            data << [offset].pack("N")
          end
        end

        data
      end

      # Subset cmap table (remap character to glyph mappings)
      #
      # Builds new cmap table with only mappings for glyphs in the subset.
      # Updates glyph IDs to new values from the mapping.
      #
      # @param table [Cmap] Parsed cmap table
      # @return [String] Binary data of subset cmap table
      def subset_cmap(table)
        # Get old mappings
        old_mappings = table.unicode_mappings
        new_mappings = {}

        # Remap to new glyph IDs
        old_mappings.each do |char_code, old_gid|
          new_gid = mapping.new_id(old_gid)
          new_mappings[char_code] = new_gid if new_gid
        end

        # Build cmap binary with new mappings
        build_cmap_binary(new_mappings)
      end

      # Subset post table (optionally drop glyph names)
      #
      # If drop_names option is set, converts to post version 3.0
      # (no glyph names). Otherwise passes through unchanged.
      #
      # @param table [Post] Parsed post table
      # @return [String] Binary data of subset post table
      def subset_post(table)
        if options.drop_names
          # Build post table version 3.0 (no glyph names)
          build_post_v3(table)
        else
          # Keep as-is
          font.table_data["post"]
        end
      end

      # Subset name table (pass through)
      #
      # Name table doesn't require subsetting, pass through unchanged.
      #
      # @param table [Name] Parsed name table
      # @return [String] Binary data of subset name table
      def subset_name(_table)
        font.table_data["name"]
      end

      # Subset head table (pass through)
      #
      # head table will have checksum updated by FontWriter,
      # no subsetting needed.
      #
      # @param table [Head] Parsed head table
      # @return [String] Binary data of subset head table
      def subset_head(_table)
        font.table_data["head"]
      end

      # Subset OS/2 table (optionally prune Unicode ranges)
      #
      # If unicode_ranges option is set, updates Unicode range bits
      # to reflect only the characters in the subset.
      #
      # @param table [Os2] Parsed OS/2 table
      # @return [String] Binary data of subset OS/2 table
      def subset_os2(_table)
        if options.unicode_ranges
          # TODO: Implement Unicode range pruning
          # For now, pass through
        end
        font.table_data["OS/2"]
      end

      private

      # Calculate numberOfHMetrics for subset
      #
      # For now, use the size of the mapping. In the future, this could
      # be optimized by finding the last unique advance width.
      #
      # @return [Integer] Number of unique advance widths
      def calculate_number_of_h_metrics
        mapping.size
      end

      # Build glyf and loca tables together
      #
      # This method extracts glyph data for all glyphs in the mapping,
      # remaps component references in compound glyphs, and builds the
      # loca offset array.
      #
      # @param glyf_table [Glyf] Parsed glyf table
      def build_glyf_and_loca(glyf_table)
        return if @glyf_data && @loca_offsets

        loca = font.table("loca")
        head = font.table("head")

        # Ensure loca is parsed
        unless loca.parsed?
          maxp = font.table("maxp")
          loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)
        end

        @glyf_data = String.new(encoding: Encoding::BINARY)
        @loca_offsets = []
        current_offset = 0

        # Process glyphs in mapping order
        mapping.each do |old_id, _new_id|
          @loca_offsets << current_offset

          # Get offset and size from original loca
          offset = loca.offset_for(old_id)
          size = loca.size_of(old_id)

          # Empty glyph
          if size.nil? || size.zero?
            next
          end

          # Extract glyph data
          glyph_data = glyf_table.raw_data[offset, size]

          # Check if compound glyph and remap components
          if compound_glyph?(glyph_data)
            glyph_data = remap_compound_glyph(glyph_data)
          end

          # Add to new glyf data
          @glyf_data << glyph_data
          current_offset += glyph_data.bytesize
        end

        # Add final offset
        @loca_offsets << current_offset
      end

      # Check if glyph data represents a compound glyph
      #
      # @param data [String] Glyph binary data
      # @return [Boolean] True if compound glyph
      def compound_glyph?(data)
        return false if data.length < 2

        num_contours_raw = data[0, 2].unpack1("n")
        num_contours = to_signed_16(num_contours_raw)
        num_contours == -1
      end

      # Remap component glyph IDs in compound glyph
      #
      # @param data [String] Original compound glyph data
      # @return [String] Remapped compound glyph data
      def remap_compound_glyph(data)
        # Create a mutable copy
        new_data = data.dup
        offset = 10 # Skip header (10 bytes)

        loop do
          break if offset >= new_data.length - 4

          # Read flags and old glyph index
          flags = new_data[offset, 2].unpack1("n")
          old_glyph_index = new_data[offset + 2, 2].unpack1("n")

          # Remap glyph index
          new_glyph_index = mapping.new_id(old_glyph_index)
          unless new_glyph_index
            raise Fontisan::SubsettingError,
                  "Component glyph #{old_glyph_index} not in subset"
          end

          # Write new glyph index
          new_data[offset + 2, 2] = [new_glyph_index].pack("n")

          # Move to next component
          offset += 4 # flags + glyph_index

          # Skip arguments
          offset += if (flags & 0x0001).zero?
                      2 # Two 8-bit arguments
                    else
                      4 # Two 16-bit arguments
                    end

          # Skip transformation
          if (flags & 0x0080) != 0
            offset += 8  # 2x2 matrix
          elsif (flags & 0x0040) != 0
            offset += 4  # X and Y scale
          elsif (flags & 0x0008) != 0
            offset += 2  # Uniform scale
          end

          # Check if more components
          break unless (flags & 0x0020) != 0
        end

        new_data
      end

      # Build cmap binary from mappings
      #
      # Creates a minimal cmap table with format 4 subtable for BMP
      # and format 12 for supplementary planes if needed.
      #
      # @param mappings [Hash<Integer, Integer>] Char code => glyph ID
      # @return [String] Binary cmap data
      def build_cmap_binary(_mappings)
        # For now, pass through original cmap
        # TODO: Implement proper cmap building
        font.table_data["cmap"]
      end

      # Build post table version 3.0 (no glyph names)
      #
      # @param table [Post] Original post table
      # @return [String] Binary post v3.0 data
      def build_post_v3(_table)
        # Post v3.0 header (32 bytes) - same as v2.0 but version = 3.0
        data = String.new(encoding: Encoding::BINARY)

        # Version 3.0
        data << [0x00030000].pack("N")

        # Copy italic angle, underline position/thickness from original
        original_data = font.table_data["post"]
        data << if original_data.length >= 32
                  # Copy fields from offset 4 to 32
                  original_data[4, 28]
                else
                  # Use defaults
                  [0, 0, 0, 0, 0, 0, 0].pack("N7")
                end

        data
      end

      # Convert unsigned 16-bit value to signed
      #
      # @param value [Integer] Unsigned 16-bit value
      # @return [Integer] Signed 16-bit value
      def to_signed_16(value)
        value > 0x7FFF ? value - 0x10000 : value
      end
    end
  end
end
