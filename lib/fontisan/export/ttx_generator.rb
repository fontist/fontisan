# frozen_string_literal: true

require "nokogiri"

module Fontisan
  module Export
    # TtxGenerator generates TTX XML format from font data
    #
    # Generates fonttools-compatible TTX XML format for font debugging
    # and interoperability. Handles various table types with appropriate
    # XML structures per the TTX specification.
    #
    # @example Generating TTX from a font
    #   generator = TtxGenerator.new(font, "font.ttf")
    #   ttx_xml = generator.generate
    #   File.write("font.ttx", ttx_xml)
    #
    # @example Selective table generation
    #   ttx_xml = generator.generate(tables: ["head", "name", "glyf"])
    class TtxGenerator
      # Initialize TTX generator
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font to export
      # @param source_path [String] Path to source font file
      # @param options [Hash] Generation options
      # @option options [Boolean] :pretty Pretty-print XML (default: true)
      # @option options [Integer] :indent Indentation spaces (default: 2)
      def initialize(font, source_path, options = {})
        @font = font
        @source_path = source_path
        @pretty = options.fetch(:pretty, true)
        @indent = options.fetch(:indent, 2)
      end

      # Generate TTX XML
      #
      # @param options [Hash] Generation options
      # @option options [Array<String>] :tables Specific tables to include
      # @return [String] TTX XML content
      def generate(options = {})
        table_list = options[:tables] || :all

        builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml.ttFont(
            "sfntVersion" => format_sfnt_version(to_int(@font.header.sfnt_version)),
            "ttLibVersion" => "4.0",
          ) do
            generate_glyph_order(xml)

            tables_to_generate = select_tables(table_list)
            tables_to_generate.each do |tag|
              generate_table(xml, tag)
            end
          end
        end

        format_output(builder.to_xml)
      end

      private

      # Convert BinData value to native Ruby integer
      #
      # @param value [Object] BinData value or integer
      # @return [Integer] Native integer
      def to_int(value)
        value.respond_to?(:to_i) ? value.to_i : value
      end

      # Generate GlyphOrder section (required first)
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @return [void]
      def generate_glyph_order(xml)
        xml.GlyphOrder do
          xml.comment(" The 'id' attribute is only for humans; it is ignored when parsed. ")
          glyph_count.times do |glyph_id|
            glyph_name = get_glyph_name(glyph_id)
            xml.GlyphID("id" => glyph_id, "name" => glyph_name)
          end
        end
      end

      # Generate individual table XML
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param tag [String] Table tag
      # @return [void]
      def generate_table(xml, tag)
        table = @font.table(tag)

        # If table can't be parsed but data exists, use binary fallback
        unless table
          if @font.table_data && @font.table_data[tag]
            generate_binary_table_from_data(xml, tag, @font.table_data[tag])
          end
          return
        end

        case tag
        when "head"
          generate_head_table(xml, table)
        when "hhea"
          generate_hhea_table(xml, table)
        when "maxp"
          generate_maxp_table(xml, table)
        when "post"
          generate_post_table(xml, table)
        when "name"
          generate_name_table(xml, table)
        when "OS/2"
          # Skip OS/2 for now - Nokogiri builder can't handle slashes in element names
          # TODO: Implement OS/2 table generation with proper XML escaping
          xml.comment(" OS/2 table skipped - requires special XML handling ")
        when "cmap"
          generate_cmap_table(xml, table)
        when "loca"
          generate_loca_table(xml, table)
        when "glyf"
          generate_glyf_table(xml, table)
        when "CFF"
          generate_cff_table(xml, table)
        when "CFF "
          generate_cff_table(xml, table)
        when "hmtx"
          generate_hmtx_table(xml, table)
        when "fvar"
          generate_fvar_table(xml, table)
        when "gvar", "cvar", "HVAR", "VVAR", "MVAR"
          generate_variation_table(xml, tag, table)
        else
          generate_binary_table(xml, tag, table)
        end
      rescue StandardError => e
        # Fallback to binary on error
        xml.comment(" Error generating #{tag}: #{e.message} ")
        generate_binary_table(xml, tag, table)
      end

      # Generate head table XML
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Tables::Head] Head table
      # @return [void]
      def generate_head_table(xml, table)
        xml.head do
          xml.comment(" Most of this table will be recalculated by the compiler ")
          xml.tableVersion("value" => format_fixed(to_int(table.version)))
          xml.fontRevision("value" => format_fixed(to_int(table.font_revision)))
          xml.checkSumAdjustment("value" => format_hex(to_int(table.checksum_adjustment)))
          xml.magicNumber("value" => format_hex(to_int(table.magic_number)))
          xml.flags("value" => to_int(table.flags))
          xml.unitsPerEm("value" => to_int(table.units_per_em))
          xml.created("value" => format_timestamp(to_int(table.created)))
          xml.modified("value" => format_timestamp(to_int(table.modified)))
          xml.xMin("value" => to_int(table.x_min))
          xml.yMin("value" => to_int(table.y_min))
          xml.xMax("value" => to_int(table.x_max))
          xml.yMax("value" => to_int(table.y_max))
          xml.macStyle("value" => format_binary_flags(to_int(table.mac_style),
                                                      16))
          xml.lowestRecPPEM("value" => to_int(table.lowest_rec_ppem))
          xml.fontDirectionHint("value" => to_int(table.font_direction_hint))
          xml.indexToLocFormat("value" => to_int(table.index_to_loc_format))
          xml.glyphDataFormat("value" => to_int(table.glyph_data_format))
        end
      end

      # Generate hhea table XML
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Tables::Hhea] Hhea table
      # @return [void]
      def generate_hhea_table(xml, table)
        xml.hhea do
          xml.tableVersion("value" => format_hex(to_int(table.version)))
          xml.ascent("value" => to_int(table.ascent))
          xml.descent("value" => to_int(table.descent))
          xml.lineGap("value" => to_int(table.line_gap))
          xml.advanceWidthMax("value" => to_int(table.advance_width_max))
          xml.minLeftSideBearing("value" => to_int(table.min_left_side_bearing))
          xml.minRightSideBearing("value" => to_int(table.min_right_side_bearing))
          xml.xMaxExtent("value" => to_int(table.x_max_extent))
          xml.caretSlopeRise("value" => to_int(table.caret_slope_rise))
          xml.caretSlopeRun("value" => to_int(table.caret_slope_run))
          xml.caretOffset("value" => to_int(table.caret_offset))
          xml.reserved0("value" => 0)
          xml.reserved1("value" => 0)
          xml.reserved2("value" => 0)
          xml.reserved3("value" => 0)
          xml.metricDataFormat("value" => to_int(table.metric_data_format))
          xml.numberOfHMetrics("value" => to_int(table.num_of_long_hor_metrics))
        end
      end

      # Generate maxp table XML
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Tables::Maxp] Maxp table
      # @return [void]
      def generate_maxp_table(xml, table)
        xml.maxp do
          xml.comment(" Most of this table will be recalculated by the compiler ")
          version = to_int(table.version)
          xml.tableVersion("value" => format_hex(version))
          xml.numGlyphs("value" => to_int(table.num_glyphs))

          if version >= 0x00010000
            xml.maxPoints("value" => to_int(table.max_points))
            xml.maxContours("value" => to_int(table.max_contours))
            xml.maxCompositePoints("value" => to_int(table.max_component_points))
            xml.maxCompositeContours("value" => to_int(table.max_component_contours))
            xml.maxZones("value" => to_int(table.max_zones))
            xml.maxTwilightPoints("value" => to_int(table.max_twilight_points))
            xml.maxStorage("value" => to_int(table.max_storage))
            xml.maxFunctionDefs("value" => to_int(table.max_function_defs))
            xml.maxInstructionDefs("value" => to_int(table.max_instruction_defs))
            xml.maxStackElements("value" => to_int(table.max_stack_elements))
            xml.maxSizeOfInstructions("value" => to_int(table.max_size_of_instructions))
            xml.maxComponentElements("value" => to_int(table.max_component_elements))
            xml.maxComponentDepth("value" => to_int(table.max_component_depth))
          end
        end
      end

      # Generate post table XML
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Tables::Post] Post table
      # @return [void]
      def generate_post_table(xml, table)
        xml.post do
          xml.formatType("value" => format_fixed(to_int(table.format)))
          xml.italicAngle("value" => format_fixed(to_int(table.italic_angle)))
          xml.underlinePosition("value" => to_int(table.underline_position))
          xml.underlineThickness("value" => to_int(table.underline_thickness))
          xml.isFixedPitch("value" => to_int(table.is_fixed_pitch))
          xml.minMemType42("value" => to_int(table.min_mem_type42))
          xml.maxMemType42("value" => to_int(table.max_mem_type42))
          xml.minMemType1("value" => to_int(table.min_mem_type1))
          xml.maxMemType1("value" => to_int(table.max_mem_type1))
        end
      end

      # Generate name table XML
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Tables::Name] Name table
      # @return [void]
      def generate_name_table(xml, table)
        xml.name do
          table.name_records.each do |record|
            xml.namerecord(
              "nameID" => to_int(record.name_id),
              "platformID" => to_int(record.platform_id),
              "platEncID" => to_int(record.encoding_id),
              "langID" => format_hex(to_int(record.language_id), width: 3),
            ) do
              xml.text(record.string)
            end
          end
        end
      end

      # Generate OS/2 table XML
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Tables::Os2] OS/2 table
      # @return [void]
      def generate_os2_table(xml, table)
        # OS/2 requires special handling due to slash in tag name
        # Generate it as a string and insert into the parent
        generate_binary_table(xml, "OS/2", table)
      end

      # Helper to add element with value attribute
      #
      # @param parent [Nokogiri::XML::Element] Parent element
      # @param name [String] Element name
      # @param value [Object] Value
      # @param doc [Nokogiri::XML::Document] Document
      # @return [void]
      def add_element_with_value(parent, name, value, doc)
        elem = doc.create_element(name)
        elem["value"] = value.to_s
        parent.add_child(elem)
      end

      # Generate binary table as hexdata
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param tag [String] Table tag
      # @param table [Object] Table object
      # @return [void]
      def generate_binary_table(xml, tag, table)
        binary_data = table.respond_to?(:to_binary_s) ? table.to_binary_s : ""
        xml.send(tag.to_sym) do
          xml.hexdata do
            xml.text("\n    #{format_hex_data(binary_data)}\n  ")
          end
        end
      end

      # Generate binary table from raw data
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param tag [String] Table tag
      # @param data [String] Raw binary data
      # @return [void]
      def generate_binary_table_from_data(xml, tag, data)
        # Remove trailing space from tag for XML element name
        clean_tag = tag.strip
        xml.send(clean_tag.to_sym) do
          xml.hexdata do
            xml.text("\n    #{format_hex_data(data)}\n  ")
          end
        end
      end

      # Generate cmap table XML (simplified for now)
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Object] Cmap table
      # @return [void]
      def generate_cmap_table(xml, table)
        generate_binary_table(xml, "cmap", table)
      end

      # Generate loca table XML
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Object] Loca table
      # @return [void]
      def generate_loca_table(xml, _table)
        xml.loca do
          xml.comment(" The 'loca' table will be calculated by the compiler ")
        end
      end

      # Generate glyf table XML (simplified for now)
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Object] Glyf table
      # @return [void]
      def generate_glyf_table(xml, table)
        generate_binary_table(xml, "glyf", table)
      end

      # Generate CFF table XML (simplified for now)
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Object] CFF table
      # @return [void]
      def generate_cff_table(xml, table)
        generate_binary_table(xml, "CFF", table)
      end

      # Generate hmtx table XML (simplified for now)
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Object] Hmtx table
      # @return [void]
      def generate_hmtx_table(xml, table)
        generate_binary_table(xml, "hmtx", table)
      end

      # Generate fvar table XML
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param table [Tables::Fvar] Fvar table
      # @return [void]
      def generate_fvar_table(xml, table)
        xml.fvar do
          xml.Version("major" => to_int(table.major_version),
                      "minor" => to_int(table.minor_version))

          table.axes.each do |axis|
            xml.Axis do
              xml.AxisTag axis.axis_tag
              xml.MinValue to_int(axis.min_value) / 65536.0
              xml.DefaultValue to_int(axis.default_value) / 65536.0
              xml.MaxValue to_int(axis.max_value) / 65536.0
              xml.AxisNameID to_int(axis.axis_name_id)
            end
          end
        end
      end

      # Generate variation table XML (gvar, cvar, HVAR, etc.)
      #
      # @param xml [Nokogiri::XML::Builder] XML builder
      # @param tag [String] Table tag
      # @param table [Object] Variation table
      # @return [void]
      def generate_variation_table(xml, tag, table)
        generate_binary_table(xml, tag, table)
      end

      # Select tables to generate
      #
      # @param table_list [Symbol, Array<String>] :all or list of tags
      # @return [Array<String>] Table tags to generate
      def select_tables(table_list)
        if table_list == :all
          @font.table_names
        else
          available = @font.table_names
          requested = Array(table_list).map(&:to_s)
          # Map CFF to "CFF " if needed
          requested = requested.map do |tag|
            if tag == "CFF" && !available.include?("CFF") && available.include?("CFF ")
              "CFF "
            else
              tag
            end
          end
          requested.select { |tag| available.include?(tag) }
        end
      end

      # Get number of glyphs
      #
      # @return [Integer] Number of glyphs
      def glyph_count
        maxp = @font.table("maxp")
        maxp ? to_int(maxp.num_glyphs) : 0
      end

      # Get glyph name by ID
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [String] Glyph name
      def get_glyph_name(glyph_id)
        post = @font.table("post")
        if post.respond_to?(:glyph_names) && post.glyph_names
          post.glyph_names[glyph_id] || ".notdef"
        elsif glyph_id.zero?
          ".notdef"
        else
          "glyph#{glyph_id.to_s.rjust(5, '0')}"
        end
      end

      # Format SFNT version
      #
      # @param version [Integer] SFNT version
      # @return [String] Formatted version as escaped bytes
      def format_sfnt_version(version)
        # Format as 4 bytes for TTX compatibility
        bytes = [version].pack("N").bytes
        "\\x#{bytes.map { |b| b.to_s(16).rjust(2, '0') }.join('\\x')}"
      end

      # Format fixed-point number (16.16)
      #
      # @param value [Integer] Fixed-point value
      # @return [String] Decimal string
      def format_fixed(value)
        result = value.to_f / 65536.0
        # Format with minimal decimal places
        if result == result.to_i
          "#{result.to_i}.0"
        else
          result.to_s
        end
      end

      # Format hex value
      #
      # @param value [Integer] Integer value
      # @param width [Integer] Minimum hex width
      # @return [String] Hex string (e.g., "0x1234")
      def format_hex(value, width: 8)
        int_value = value.respond_to?(:to_i) ? value.to_i : value
        "0x#{int_value.to_s(16).rjust(width, '0')}"
      end

      # Format binary flags
      #
      # @param value [Integer] Integer value
      # @param bits [Integer] Number of bits
      # @return [String] Binary string with spaces every 8 bits
      def format_binary_flags(value, bits)
        binary = value.to_s(2).rjust(bits, "0")
        # Add spaces every 8 bits from left
        binary.scan(/.{1,8}/).join(" ")
      end

      # Format timestamp
      #
      # @param timestamp [Integer] Mac timestamp (seconds since 1904-01-01)
      # @return [String] Human-readable date string
      def format_timestamp(timestamp)
        # Mac epoch: Jan 1, 1904 00:00:00 UTC
        mac_epoch = Time.utc(1904, 1, 1)
        time = mac_epoch + timestamp
        time.strftime("%a %b %e %H:%M:%S %Y")
      rescue StandardError
        "Invalid Date"
      end

      # Format binary data as hex
      #
      # @param data [String] Binary data
      # @return [String] Hex string with newlines every 32 bytes
      def format_hex_data(data)
        hex = data.unpack1("H*")
        # Format in lines of 64 hex chars (32 bytes) for readability
        hex.scan(/.{1,64}/).join("\n    ")
      end

      # Format output XML
      #
      # @param xml [String] Raw XML
      # @return [String] Formatted XML
      def format_output(xml)
        if @pretty
          doc = Nokogiri::XML(xml)
          doc.to_xml(indent: @indent)
        else
          # Remove extra whitespace for compact format
          xml.gsub(/>\s+</, "><").gsub(/\n\s*/, "")
        end
      end
    end
  end
end
