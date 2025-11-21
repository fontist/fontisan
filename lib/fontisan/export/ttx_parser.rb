# frozen_string_literal: true

require "nokogiri"

module Fontisan
  module Export
    # TtxParser parses TTX XML format to font data
    #
    # Parses fonttools-compatible TTX XML files and reconstructs
    # font data that can be written back to binary formats.
    #
    # @example Parsing TTX file
    #   parser = TtxParser.new
    #   font_data = parser.parse(File.read("font.ttx"))
    #   # Use font_data to rebuild binary font
    class TtxParser
      # Parse TTX XML content
      #
      # @param ttx_xml [String] TTX XML content
      # @return [Hash] Parsed font data structure
      def parse(ttx_xml)
        doc = Nokogiri::XML(ttx_xml)
        ttfont = doc.at_xpath("/ttFont")
        raise "No ttFont root element found" unless ttfont

        {
          sfnt_version: parse_sfnt_version(ttfont["sfntVersion"]),
          glyph_order: parse_glyph_order(ttfont),
          tables: parse_tables(ttfont),
        }
      end

      private

      # Parse SFNT version
      #
      # @param version_str [String] Version string
      # @return [Integer] Version integer
      def parse_sfnt_version(version_str)
        # Handle format like "\x00\x01\x00\x00" or "0x00010000"
        if version_str.start_with?("\\x")
          # Parse escaped hex bytes
          bytes = version_str.scan(/\\x([0-9a-f]{2})/i).flatten
          bytes.map { |b| b.to_i(16) }.pack("C*").unpack1("N")
        elsif version_str.start_with?("0x")
          version_str.to_i(16)
        else
          version_str.to_i
        end
      end

      # Parse GlyphOrder section
      #
      # @param ttfont [Nokogiri::XML::Element] Root element
      # @return [Array<Hash>] Array of glyph entries
      def parse_glyph_order(ttfont)
        glyph_order = ttfont.at_xpath("GlyphOrder")
        return [] unless glyph_order

        glyph_order.xpath("GlyphID").map do |glyph_id|
          {
            id: glyph_id["id"].to_i,
            name: glyph_id["name"],
          }
        end
      end

      # Parse all tables
      #
      # @param ttfont [Nokogiri::XML::Element] Root element
      # @return [Hash] Hash of table data by tag
      def parse_tables(ttfont)
        tables = {}

        # Parse specific tables
        parse_head_table(ttfont, tables)
        parse_hhea_table(ttfont, tables)
        parse_maxp_table(ttfont, tables)
        parse_name_table(ttfont, tables)
        parse_os2_table(ttfont, tables)
        parse_post_table(ttfont, tables)

        # Parse any remaining binary tables
        parse_binary_tables(ttfont, tables)

        tables
      end

      # Parse head table
      #
      # @param ttfont [Nokogiri::XML::Element] Root element
      # @param tables [Hash] Tables hash
      # @return [void]
      def parse_head_table(ttfont, tables)
        head = ttfont.at_xpath("head")
        return unless head

        tables["head"] = {
          table_version: parse_fixed(head.at_xpath("tableVersion")&.[]("value")),
          font_revision: parse_fixed(head.at_xpath("fontRevision")&.[]("value")),
          checksum_adjustment: parse_hex(head.at_xpath("checkSumAdjustment")&.[]("value")),
          magic_number: parse_hex(head.at_xpath("magicNumber")&.[]("value")),
          flags: head.at_xpath("flags")&.[]("value").to_i,
          units_per_em: head.at_xpath("unitsPerEm")&.[]("value").to_i,
          created: parse_timestamp(head.at_xpath("created")&.[]("value")),
          modified: parse_timestamp(head.at_xpath("modified")&.[]("value")),
          x_min: head.at_xpath("xMin")&.[]("value").to_i,
          y_min: head.at_xpath("yMin")&.[]("value").to_i,
          x_max: head.at_xpath("xMax")&.[]("value").to_i,
          y_max: head.at_xpath("yMax")&.[]("value").to_i,
          mac_style: parse_binary_flags(head.at_xpath("macStyle")&.[]("value")),
          lowest_rec_ppem: head.at_xpath("lowestRecPPEM")&.[]("value").to_i,
          font_direction_hint: head.at_xpath("fontDirectionHint")&.[]("value").to_i,
          index_to_loc_format: head.at_xpath("indexToLocFormat")&.[]("value").to_i,
          glyph_data_format: head.at_xpath("glyphDataFormat")&.[]("value").to_i,
        }
      end

      # Parse hhea table
      #
      # @param ttfont [Nokogiri::XML::Element] Root element
      # @param tables [Hash] Tables hash
      # @return [void]
      def parse_hhea_table(ttfont, tables)
        hhea = ttfont.at_xpath("hhea")
        return unless hhea

        tables["hhea"] = {
          table_version: parse_hex(hhea.at_xpath("tableVersion")&.[]("value")),
          ascent: hhea.at_xpath("ascent")&.[]("value").to_i,
          descent: hhea.at_xpath("descent")&.[]("value").to_i,
          line_gap: hhea.at_xpath("lineGap")&.[]("value").to_i,
          advance_width_max: hhea.at_xpath("advanceWidthMax")&.[]("value").to_i,
          min_left_side_bearing: hhea.at_xpath("minLeftSideBearing")&.[]("value").to_i,
          min_right_side_bearing: hhea.at_xpath("minRightSideBearing")&.[]("value").to_i,
          x_max_extent: hhea.at_xpath("xMaxExtent")&.[]("value").to_i,
          caret_slope_rise: hhea.at_xpath("caretSlopeRise")&.[]("value").to_i,
          caret_slope_run: hhea.at_xpath("caretSlopeRun")&.[]("value").to_i,
          caret_offset: hhea.at_xpath("caretOffset")&.[]("value").to_i,
          metric_data_format: hhea.at_xpath("metricDataFormat")&.[]("value").to_i,
          number_of_h_metrics: hhea.at_xpath("numberOfHMetrics")&.[]("value").to_i,
        }
      end

      # Parse maxp table
      #
      # @param ttfont [Nokogiri::XML::Element] Root element
      # @param tables [Hash] Tables hash
      # @return [void]
      def parse_maxp_table(ttfont, tables)
        maxp = ttfont.at_xpath("maxp")
        return unless maxp

        tables["maxp"] = {
          table_version: parse_hex(maxp.at_xpath("tableVersion")&.[]("value")),
          num_glyphs: maxp.at_xpath("numGlyphs")&.[]("value").to_i,
        }

        # Version 1.0 fields
        if tables["maxp"][:table_version] >= 0x00010000
          tables["maxp"].merge!({
                                  max_points: maxp.at_xpath("maxPoints")&.[]("value")&.to_i,
                                  max_contours: maxp.at_xpath("maxContours")&.[]("value")&.to_i,
                                  max_composite_points: maxp.at_xpath("maxCompositePoints")&.[]("value")&.to_i,
                                  max_composite_contours: maxp.at_xpath("maxCompositeContours")&.[]("value")&.to_i,
                                })
        end
      end

      # Parse name table
      #
      # @param ttfont [Nokogiri::XML::Element] Root element
      # @param tables [Hash] Tables hash
      # @return [void]
      def parse_name_table(ttfont, tables)
        name_elem = ttfont.at_xpath("name")
        return unless name_elem

        name_records = name_elem.xpath("namerecord").map do |record|
          {
            name_id: record["nameID"].to_i,
            platform_id: record["platformID"].to_i,
            encoding_id: record["platEncID"].to_i,
            language_id: parse_hex(record["langID"]),
            string: record.text,
          }
        end

        tables["name"] = { name_records: name_records }
      end

      # Parse OS/2 table (stub)
      #
      # @param ttfont [Nokogiri::XML::Element] Root element
      # @param tables [Hash] Tables hash
      # @return [void]
      def parse_os2_table(ttfont, tables)
        os2 = ttfont.at_xpath("OS/2")
        return unless os2

        # Basic OS/2 parsing - can be expanded
        tables["OS/2"] = { parsed: false }
      end

      # Parse post table (stub)
      #
      # @param ttfont [Nokogiri::XML::Element] Root element
      # @param tables [Hash] Tables hash
      # @return [void]
      def parse_post_table(ttfont, tables)
        post = ttfont.at_xpath("post")
        return unless post

        tables["post"] = {
          format_type: parse_fixed(post.at_xpath("formatType")&.[]("value")),
          italic_angle: parse_fixed(post.at_xpath("italicAngle")&.[]("value")),
          underline_position: post.at_xpath("underlinePosition")&.[]("value").to_i,
          underline_thickness: post.at_xpath("underlineThickness")&.[]("value").to_i,
          is_fixed_pitch: post.at_xpath("isFixedPitch")&.[]("value").to_i,
        }
      end

      # Parse binary tables (fallback)
      #
      # @param ttfont [Nokogiri::XML::Element] Root element
      # @param tables [Hash] Tables hash
      # @return [void]
      def parse_binary_tables(ttfont, tables)
        # Find all table elements not already parsed
        ttfont.children.each do |elem|
          next unless elem.element?
          next if elem.name == "GlyphOrder"
          next if tables.key?(elem.name)

          hexdata = elem.at_xpath("hexdata")
          if hexdata
            tables[elem.name] = {
              binary: parse_hex_data(hexdata.text),
            }
          end
        end
      end

      # Parse fixed-point number
      #
      # @param value_str [String] Fixed-point string
      # @return [Integer] Fixed-point integer (16.16)
      def parse_fixed(value_str)
        return 0 unless value_str

        (value_str.to_f * 65536).to_i
      end

      # Parse hex value
      #
      # @param value_str [String] Hex string
      # @return [Integer] Integer value
      def parse_hex(value_str)
        return 0 unless value_str

        value_str.to_i(16)
      end

      # Parse binary flags
      #
      # @param flags_str [String] Binary string with spaces
      # @return [Integer] Integer value
      def parse_binary_flags(flags_str)
        return 0 unless flags_str

        flags_str.gsub(/\s+/, "").to_i(2)
      end

      # Parse timestamp
      #
      # @param timestamp_str [String] Timestamp string
      # @return [Integer] Mac timestamp
      def parse_timestamp(timestamp_str)
        return 0 unless timestamp_str

        begin
          time = Time.strptime(timestamp_str, "%a %b %e %H:%M:%S %Y")
          mac_epoch = Time.utc(1904, 1, 1)
          (time - mac_epoch).to_i
        rescue StandardError
          0
        end
      end

      # Parse hex data
      #
      # @param hex_str [String] Hex string with newlines
      # @return [String] Binary data
      def parse_hex_data(hex_str)
        hex_clean = hex_str.gsub(/\s+/, "")
        [hex_clean].pack("H*")
      end
    end
  end
end
