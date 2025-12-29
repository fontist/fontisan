# frozen_string_literal: true

module Fontisan
  module Formatters
    # TextFormatter formats model objects into human-readable text output.
    #
    # This formatter handles Models::FontInfo and Models::TableInfo objects,
    # presenting them with proper alignment and spacing for terminal display.
    #
    # @example Format font information
    #   formatter = TextFormatter.new
    #   text = formatter.format(font_info)
    #   puts text
    class TextFormatter
      # Format a model object into human-readable text.
      #
      # @param model [Object] The model to format (FontInfo, TableInfo, etc.)
      # @return [String] Formatted text representation
      def format(model)
        case model
        when Models::FontInfo
          format_font_info(model)
        when Models::TableInfo
          format_table_info(model)
        when Models::GlyphInfo
          format_glyph_info(model)
        when Models::UnicodeMappings
          format_unicode_mappings(model)
        when Models::VariableFontInfo
          format_variable_font_info(model)
        when Models::OpticalSizeInfo
          format_optical_size_info(model)
        when Models::ScriptsInfo
          format_scripts_info(model)
        when Models::AllScriptsFeaturesInfo
          format_all_scripts_features_info(model)
        when Models::FeaturesInfo
          format_features_info(model)
        when Models::CollectionListInfo
          format_collection_list_info(model)
        when Models::FontSummary
          format_font_summary(model)
        when Models::CollectionInfo
          format_collection_info(model)
        when Models::CollectionBriefInfo
          format_collection_brief_info(model)
        else
          model.to_s
        end
      end

      private

      # Format FontInfo as human-readable text.
      #
      # @param info [Models::FontInfo] Font information to format
      # @return [String] Formatted text with aligned labels and values
      def format_font_info(info)
        lines = []

        # Font type should be first (formatted for display)
        font_type_display = format_font_type_display(info.font_format,
                                                     info.is_variable)
        add_line(lines, "Font type", font_type_display)

        add_line(lines, "Family", info.family_name)
        add_line(lines, "Subfamily", info.subfamily_name)
        add_line(lines, "Full name", info.full_name)
        add_line(lines, "PostScript name", info.postscript_name)
        add_line(lines, "PostScript CID name", info.postscript_cid_name)
        add_line(lines, "Preferred family", info.preferred_family)
        add_line(lines, "Preferred subfamily", info.preferred_subfamily)
        add_line(lines, "Mac font menu name", info.mac_font_menu_name)
        add_line(lines, "Version", info.version)
        add_line(lines, "Unique ID", info.unique_id)
        add_line(lines, "Description", info.description)
        add_line(lines, "Designer", info.designer)
        add_line(lines, "Designer URL", info.designer_url)
        add_line(lines, "Manufacturer", info.manufacturer)
        add_line(lines, "Vendor URL", info.vendor_url)
        add_line(lines, "Vendor ID", info.vendor_id)
        add_line(lines, "Trademark", info.trademark)
        add_line(lines, "Copyright", info.copyright)
        add_line(lines, "License Description", info.license_description)
        add_line(lines, "License URL", info.license_url)
        add_line(lines, "Sample text", info.sample_text)
        add_line(lines, "Font revision", format_float(info.font_revision))
        add_line(lines, "Permissions", info.permissions)
        add_line(lines, "Units per em", info.units_per_em)

        lines.join("\n")
      end

      # Format TableInfo as human-readable text.
      #
      # @param info [Models::TableInfo] Table information to format
      # @return [String] Formatted text with table directory listing
      def format_table_info(info)
        lines = []
        lines << "SFNT Version: #{info.sfnt_version}"
        lines << "Number of tables: #{info.num_tables}"
        lines << ""
        lines << "Tables:"

        # Find max tag length for alignment
        max_tag_len = info.tables.map { |t| t.tag.length }.max || 4

        info.tables.each do |table|
          tag = table.tag.ljust(max_tag_len)
          lines << Kernel.format("  %<tag>s  %<length>10d bytes  (offset: %<offset>d, checksum: 0x%<checksum>08X)",
                                 tag: tag, length: table.length, offset: table.offset, checksum: table.checksum)
        end

        lines.join("\n")
      end

      # Format GlyphInfo as human-readable text.
      #
      # @param info [Models::GlyphInfo] Glyph information to format
      # @return [String] Formatted text with glyph names
      def format_glyph_info(info)
        lines = []

        if info.glyph_names.empty?
          lines << "No glyph name information available"
          lines << "Source: #{info.source}"
        else
          lines << "Glyph count: #{info.glyph_count}"
          lines << "Source: #{info.source}"
          lines << ""
          lines << "Glyph names:"

          info.glyph_names.each_with_index do |name, index|
            lines << Kernel.format("  %5d  %s", index, name)
          end
        end

        lines.join("\n")
      end

      # Format UnicodeMappings as human-readable text.
      #
      # @param mappings [Models::UnicodeMappings] Unicode mappings to format
      # @return [String] Formatted text with Unicode to glyph mappings
      def format_unicode_mappings(mappings)
        lines = []

        if mappings.mappings.empty?
          lines << "No Unicode mappings available"
        else
          lines << "Unicode mappings: #{mappings.count}"
          lines << ""

          mappings.mappings.each do |mapping|
            lines << if mapping.glyph_name
                       "#{mapping.codepoint}  glyph #{mapping.glyph_index}  #{mapping.glyph_name}"
                     else
                       "#{mapping.codepoint}  glyph #{mapping.glyph_index}"
                     end
          end
        end

        lines.join("\n")
      end

      # Format VariableFontInfo as human-readable text.
      #
      # @param info [Models::VariableFontInfo] Variable font information to format
      # @return [String] Formatted text with axes and instances
      def format_variable_font_info(info)
        lines = []

        unless info.is_variable
          lines << "Not a variable font"
          return lines.join("\n")
        end

        info.axes.each_with_index do |axis, i|
          lines << "Axis #{i}:                 #{axis.tag}"
          lines << "Axis #{i} name:            #{axis.name}" if axis.name
          lines << "Axis #{i} range:           #{format_float(axis.min_value)} #{format_float(axis.max_value)}"
          lines << "Axis #{i} default:         #{format_float(axis.default_value)}"
        end

        info.instances.each_with_index do |instance, i|
          lines << "Instance #{i} name:        #{instance.name}"
          coordinates = instance.coordinates.map do |c|
            format_float(c)
          end.join(" ")
          lines << "Instance #{i} position:    #{coordinates}"
        end

        lines.join("\n")
      end

      # Format OpticalSizeInfo as human-readable text.
      #
      # @param info [Models::OpticalSizeInfo] Optical size information to format
      # @return [String] Formatted text with optical size range
      def format_optical_size_info(info)
        return "No optical size information" unless info.has_optical_size

        "Size range: [#{format_float(info.lower_point_size)}, #{format_float(info.upper_point_size)}) pt  (source: #{info.source})"
      end

      # Format ScriptsInfo as human-readable text.
      #
      # @param info [Models::ScriptsInfo] Scripts information to format
      # @return [String] Formatted text with script tags and descriptions
      def format_scripts_info(info)
        lines = []

        if info.scripts.empty?
          lines << "No scripts found"
        else
          lines << "Script count: #{info.script_count}"
          lines << ""

          info.scripts.each do |script|
            lines << "#{script.tag}  #{script.description}"
          end
        end

        lines.join("\n")
      end

      # Format AllScriptsFeaturesInfo as human-readable text.
      #
      # @param info [Models::AllScriptsFeaturesInfo] All scripts features information to format
      # @return [String] Formatted text with features for all scripts
      def format_all_scripts_features_info(info)
        lines = []

        info.scripts_features.each_with_index do |script_features, index|
          lines << "" if index.positive? # Add blank line between scripts
          lines << "Script: #{script_features.script}"
          lines << "Feature count: #{script_features.feature_count}"
          lines << ""

          if script_features.features.empty?
            lines << "  No features found"
          else
            script_features.features.each do |feature|
              lines << "  #{feature.tag}  #{feature.description}"
            end
          end
        end

        lines.join("\n")
      end

      # Format FeaturesInfo as human-readable text.
      #
      # @param info [Models::FeaturesInfo] Features information to format
      # @return [String] Formatted text with feature tags and descriptions
      def format_features_info(info)
        lines = []

        if info.features.empty?
          lines << "No features found for script '#{info.script}'"
        else
          lines << "Script: #{info.script}"
          lines << "Feature count: #{info.feature_count}"
          lines << ""

          info.features.each do |feature|
            lines << "#{feature.tag}  #{feature.description}"
          end
        end

        lines.join("\n")
      end

      # Add a formatted line to the output if the value is present.
      #
      # @param lines [Array<String>] Output lines array
      # @param label [String] Field label
      # @param value [Object] Field value (skipped if nil or empty string)
      def add_line(lines, label, value)
        return if value.nil? || (value.is_a?(String) && value.empty?)

        formatted_label = "#{label}:".ljust(25)
        lines << "#{formatted_label} #{value}"
      end

      # Format a float value for display.
      #
      # @param value [Float, nil] Float value to format
      # @return [String, nil] Formatted float or nil if input is nil
      def format_float(value)
        return nil if value.nil?

        # Format to 5 decimal places, remove trailing zeros
        formatted = Kernel.format("%<value>.5f", value: value)
        formatted.sub(/\.?0+$/, "")
      end

      # Format font type for human-readable display.
      #
      # @param font_format [String] Enumerated font format code
      # @param is_variable [Boolean] Whether font is variable
      # @return [String, nil] Formatted font type or nil if font_format is nil
      def format_font_type_display(font_format, is_variable)
        return nil if font_format.nil?

        type = case font_format
               when "truetype"
                 "TrueType"
               when "cff"
                 "OpenType (CFF)"
               when "unknown"
                 "Unknown"
               else
                 font_format
               end

        # Always show variable status explicitly
        type += is_variable ? " (Variable)" : " (Not Variable)"
        type
      end

      # Format CollectionListInfo as human-readable text.
      #
      # @param info [Models::CollectionListInfo] Collection list information to format
      # @return [String] Formatted text with fonts in collection
      def format_collection_list_info(info)
        lines = []

        lines << "Collection: #{info.collection_path}"
        lines << "Fonts: #{info.num_fonts}"
        lines << ""

        info.fonts.each do |font|
          lines << "#{font.index}. #{font.family_name} #{font.subfamily_name}"
          lines << "   PostScript: #{font.postscript_name}"
          lines << "   Format: #{font.font_format}"
          lines << "   Glyphs: #{font.num_glyphs}, Tables: #{font.num_tables}"
          lines << "" unless font.index == info.num_fonts - 1
        end

        lines.join("\n")
      end

      # Format FontSummary as human-readable text.
      #
      # @param summary [Models::FontSummary] Font summary to format
      # @return [String] Formatted text with font summary
      def format_font_summary(summary)
        lines = []

        lines << "Font: #{summary.font_path}"
        lines << "Family: #{summary.family_name} #{summary.subfamily_name}"
        lines << "Format: #{summary.font_format}"
        lines << "Glyphs: #{summary.num_glyphs}"
        lines << "Tables: #{summary.num_tables}"

        lines.join("\n")
      end

      # Format CollectionInfo as human-readable text.
      #
      # @param info [Models::CollectionInfo] Collection information to format
      # @return [String] Formatted text with collection metadata
      def format_collection_info(info)
        lines = []

        # Header section
        lines << "=== Collection Information ==="
        lines << ""
        lines << "File: #{info.collection_path}"
        lines << "Format: #{info.collection_format}"
        lines << "Size: #{format_bytes(info.file_size_bytes)}"
        lines << ""

        # Header details
        lines << "=== Header ==="
        lines << "Tag: #{info.ttc_tag}"
        lines << "Version: #{info.version_string} (#{info.version_hex})"
        lines << "Number of fonts: #{info.num_fonts}"
        lines << ""

        # Font offsets
        lines << "=== Font Offsets ==="
        info.font_offsets.each_with_index do |offset, index|
          lines << Kernel.format("  %d. Offset: %8d (0x%08X)",
                                 index, offset, offset)
        end
        lines << ""

        # Table sharing statistics
        if info.table_sharing
          lines << "=== Table Sharing ==="
          lines << "Shared tables: #{info.table_sharing.shared_tables}"
          lines << "Unique tables: #{info.table_sharing.unique_tables}"
          lines << "Sharing: #{format_float(info.table_sharing.sharing_percentage)}%"
          lines << "Space saved: #{format_bytes(info.table_sharing.space_saved_bytes)}"
        end

        lines.join("\n")
      end

      # Format CollectionBriefInfo as human-readable text.
      #
      # @param info [Models::CollectionBriefInfo] Collection brief information to format
      # @return [String] Formatted text with collection header and each font's brief info
      def format_collection_brief_info(info)
        lines = []

        # Collection header
        lines << "Collection: #{info.collection_path}"
        lines << "Fonts: #{info.num_fonts}"
        lines << ""

        # Each font's brief info
        info.fonts.each_with_index do |font_info, index|
          # Show font index with offset
          if font_info.collection_offset
            lines << "Font #{index} (offset: #{font_info.collection_offset}):"
          else
            lines << "Font #{index}:"
          end
          lines << ""

          # Format each font using same structure as individual fonts
          font_type_display = format_font_type_display(font_info.font_format, font_info.is_variable)
          add_line(lines, "Font type", font_type_display)
          add_line(lines, "Family", font_info.family_name)
          add_line(lines, "Subfamily", font_info.subfamily_name)
          add_line(lines, "Full name", font_info.full_name)
          add_line(lines, "PostScript name", font_info.postscript_name)
          add_line(lines, "Version", font_info.version)
          add_line(lines, "Vendor ID", font_info.vendor_id)
          add_line(lines, "Font revision", format_float(font_info.font_revision))
          add_line(lines, "Units per em", font_info.units_per_em)

          # Blank line between fonts (except after last)
          lines << "" unless index == info.num_fonts - 1
        end

        lines.join("\n")
      end

      # Format bytes for human-readable display.
      #
      # @param bytes [Integer] Number of bytes
      # @return [String] Formatted byte size
      def format_bytes(bytes)
        return "0 B" if bytes.nil? || bytes.zero?

        if bytes < 1024
          "#{bytes} B"
        elsif bytes < 1024 * 1024
          "#{(bytes / 1024.0).round(2)} KB"
        else
          "#{(bytes / (1024.0 * 1024)).round(2)} MB"
        end
      end
    end
  end
end
