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
        @subset_bbox = nil      # [xMin, yMin, xMax, yMax] over actual subset glyphs
        @subset_max_advance = 0 # largest advanceWidth in subset hmtx
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

      # Subset hhea table (update numberOfHMetrics + advanceWidthMax)
      #
      # Updates numberOfHMetrics to reflect the subset's glyph count and
      # recomputes advanceWidthMax from the subset's actual hmtx. The
      # source TTC's advanceWidthMax covers every donor font and is far
      # larger than any per-block subset needs.
      #
      # @param table [Hhea] Parsed hhea table
      # @param hmtx [Hmtx, nil] Optional parsed hmtx table (for calculating metrics)
      # @return [String] Binary data of subset hhea table
      def subset_hhea(table, hmtx = nil)
        data = table.to_binary_s.dup

        # Calculate new numberOfHMetrics
        new_num_h_metrics = if hmtx&.h_metrics
                              hmtx.h_metrics.size
                            else
                              calculate_number_of_h_metrics
                            end

        # numberOfHMetrics at offset 34 (uint16)
        data[34, 2] = [new_num_h_metrics].pack("n")

        # advanceWidthMax at offset 10 (uint16). Recompute from subset
        # hmtx so a per-block subset doesn't keep the source TTC's
        # max (which can be 4x larger than any glyph in the subset).
        # Tables are processed alphabetically (hhea before hmtx), so
        # we read hmtx directly here rather than relying on a cached
        # value from subset_hmtx.
        new_max = compute_subset_max_advance
        data[10, 2] = [new_max].pack("n") if new_max.positive?

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

        max_advance = 0
        mapping.old_ids.each do |old_id|
          metric = table.metric_for(old_id)
          next unless metric

          advance = metric[:advance_width]
          max_advance = advance if advance && advance > max_advance
          data << [advance].pack("n")
          data << [metric[:lsb]].pack("n")
        end

        @subset_max_advance = max_advance
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
      # Subset head table (recompute bbox from actual subset glyphs)
      #
      # The source TTC's head.xMin/yMin/xMax/yMax covers every donor
      # font in the collection — far larger than any per-block subset.
      # Browsers and layout engines use head bbox (plus hhea + OS/2)
      # to compute line height and clip text; a too-large bbox makes
      # glyphs render at the wrong visual size.
      #
      # @param _table [Head] Parsed head table (unused; we re-serialize
      #   directly from font.table_data so we don't lose other fields)
      # @return [String] Binary data of subset head table
      def subset_head(_table)
        # Trigger glyf build (which populates @subset_bbox) if not done.
        glyf = font.table("glyf")
        build_glyf_and_loca(glyf) unless @glyf_data

        data = font.table_data["head"].dup

        if @subset_bbox
          x_min, y_min, x_max, y_max = @subset_bbox
          # head layout: xMin at offset 36, yMin 38, xMax 40, yMax 42
          # (each int16, big-endian, signed)
          data[36, 8] = [x_min, y_min, x_max, y_max].pack("n4")
        end

        data
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

      # Compute the largest advanceWidth across all subset glyphs by
      # reading the source hmtx directly. Called from subset_hhea
      # because hhea is processed before hmtx (alphabetical order).
      #
      # @return [Integer] max advanceWidth, or 0 if no metrics found
      def compute_subset_max_advance
        hmtx = font.table("hmtx")
        return 0 unless hmtx

        unless hmtx.parsed?
          hhea = font.table("hhea")
          maxp = font.table("maxp")
          hmtx.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)
        end

        max_advance = 0
        mapping.old_ids.each do |old_id|
          metric = hmtx.metric_for(old_id)
          next unless metric

          advance = metric[:advance_width]
          max_advance = advance if advance && advance > max_advance
        end
        max_advance
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

        # Track union bbox across all subset glyphs. Glyph binary layout:
        #   int16 numberOfContours (offset 0)
        #   int16 xMin (offset 2)
        #   int16 yMin (offset 4)
        #   int16 xMax (offset 6)
        #   int16 yMax (offset 8)
        bbox_x_min = 1 << 30
        bbox_y_min = 1 << 30
        bbox_x_max = -(1 << 30)
        bbox_y_max = -(1 << 30)

        # Process glyphs in mapping order
        mapping.old_ids.each do |old_id|
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

          # Update bbox union. Each glyph has at least 10 bytes of
          # header (numberOfContours + 4 int16 bbox fields).
          if glyph_data.bytesize >= 10
            _n, gx_min, gy_min, gx_max, gy_max = glyph_data[0, 10].unpack("n5")
            # Treat as signed int16
            gx_min = (gx_min ^ 0x8000) - 0x8000
            gy_min = (gy_min ^ 0x8000) - 0x8000
            gx_max = (gx_max ^ 0x8000) - 0x8000
            gy_max = (gy_max ^ 0x8000) - 0x8000
            bbox_x_min = gx_min if gx_min < bbox_x_min
            bbox_y_min = gy_min if gy_min < bbox_y_min
            bbox_x_max = gx_max if gx_max > bbox_x_max
            bbox_y_max = gy_max if gy_max > bbox_y_max
          end

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

        # Stash union bbox if we saw at least one non-empty glyph.
        return if bbox_x_min > bbox_x_max

        @subset_bbox = [bbox_x_min, bbox_y_min, bbox_x_max, bbox_y_max]
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
      # @param mappings [Hash<Integer, Integer>] Char code => new glyph ID
      # @return [String] Binary cmap data
      def build_cmap_binary(mappings)
        # Edge case: empty mappings (e.g., block with no covered chars).
        # Emit a minimal valid cmap with one format 4 subtable mapping
        # only U+0000 → .notdef so the table isn't empty.
        mappings = { 0 => 0 } if mappings.empty?

        bmp = mappings.select { |cp, _| cp <= 0xFFFF }
        supp = mappings.select { |cp, _| cp > 0xFFFF }

        subtables = []
        records = [] # [platform_id, encoding_id, subtable_index]

        unless bmp.empty?
          subtables << build_cmap_format_4(bmp)
          idx = subtables.size - 1
          records << [3, 1, idx] # Windows BMP
          records << [0, 3, idx] # Unicode BMP
        end

        unless supp.empty?
          # Format 12 covers both BMP and supplementary — include all
          # mappings so a single subtable covers the full range.
          subtables << build_cmap_format_12(mappings)
          idx = subtables.size - 1
          records << [3, 10, idx] # Windows UCS-4
          records << [0, 4, idx]  # Unicode full
        end

        # Header: version (uint16) + numTables (uint16)
        num_tables = records.size
        header = [0, num_tables].pack("nn")

        # Encoding records start immediately after the header.
        # Each record is 8 bytes; subtables follow.
        subtable_base = 4 + (8 * num_tables)

        offsets = []
        running = subtable_base
        subtables.each do |st|
          offsets << running
          running += st.bytesize
        end

        record_bytes = +""
        records.each do |pid, eid, idx|
          record_bytes << [pid, eid, offsets[idx]].pack("nnN")
        end

        header + record_bytes + subtables.join
      end

      # Format 4 subtable: segment-mapping with idDelta, suitable for
      # BMP codepoints (U+0000..U+FFFF). Builds compact segments where
      # consecutive codepoints map to consecutive glyph IDs.
      def build_cmap_format_4(bmp_mappings)
        segments = coalesce_segments(bmp_mappings)
        # Mandatory final segment: U+FFFF → gid 0 (per OpenType spec).
        segments << { start_cp: 0xFFFF, end_cp: 0xFFFF, start_gid: 0 }

        seg_count = segments.size
        seg_count_x2 = seg_count * 2
        search_range = 2**Math.log2(seg_count).floor * 2
        search_range = 2 if search_range < 2
        entry_selector = Math.log2(search_range / 2).to_i
        range_shift = seg_count_x2 - search_range

        end_codes = segments.map { |s| s[:end_cp] }
        start_codes = segments.map { |s| s[:start_cp] }
        # idDelta is int16 stored as uint16 (two's complement). For a
        # sequential segment, idDelta = (start_gid - start_cp) & 0xFFFF.
        id_deltas = segments.map { |s| (s[:start_gid] - s[:start_cp]) & 0xFFFF }
        id_range_offsets = [0] * seg_count

        subtable = +""
        subtable << [4, 0, 0, seg_count_x2,
                     search_range, entry_selector, range_shift].pack("n*")
        subtable << end_codes.pack("n*")
        subtable << [0].pack("n") # reservedPad
        subtable << start_codes.pack("n*")
        subtable << id_deltas.pack("n*")
        subtable << id_range_offsets.pack("n*")

        # Patch the length field (was placeholder 0).
        subtable[2, 2] = [subtable.bytesize].pack("n")
        subtable
      end

      # Format 12 subtable: segmented coverage for full Unicode range.
      # Simpler than format 4 — just (start_char, end_char, start_gid)
      # triples with no delta/offset indirection.
      def build_cmap_format_12(all_mappings)
        groups = coalesce_segments(all_mappings)
        num_groups = groups.size

        subtable = +""
        subtable << [12, 0, 0, 0, num_groups].pack("nnNNN")
        groups.each do |g|
          subtable << [g[:start_cp], g[:end_cp], g[:start_gid]].pack("NNN")
        end

        # Patch the length field (was placeholder 0). Total length is
        # 16-byte header + 12 bytes per group.
        subtable[4, 4] = [subtable.bytesize].pack("N")
        subtable
      end

      # Group codepoints into consecutive runs where both codepoint AND
      # glyph ID are sequential. Each run becomes one segment/group.
      def coalesce_segments(mappings)
        sorted = mappings.sort_by { |cp, _| cp }
        segments = []
        current = nil
        sorted.each do |cp, gid|
          if current && cp == current[:end_cp] + 1 && gid == current[:start_gid] + (cp - current[:start_cp])
            current[:end_cp] = cp
          else
            segments << current if current
            current = { start_cp: cp, end_cp: cp, start_gid: gid }
          end
        end
        segments << current if current
        segments
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
