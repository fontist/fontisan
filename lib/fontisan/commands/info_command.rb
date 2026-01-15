# frozen_string_literal: true

module Fontisan
  module Commands
    # Command to extract font or collection metadata information.
    #
    # This command auto-detects whether the input is a collection (TTC/OTC)
    # or individual font (TTF/OTF) and returns the appropriate model:
    # - CollectionInfo for TTC/OTC files
    # - FontInfo for TTF/OTF files
    #
    # For individual fonts, extracts comprehensive information from various tables:
    # - name table: family names, version, copyright, etc.
    # - OS/2 table: vendor ID, embedding permissions
    # - head table: font revision, units per em
    #
    # @example Extract font information
    #   command = InfoCommand.new("path/to/font.ttf")
    #   info = command.run
    #   puts info.family_name
    #
    # @example Extract collection information
    #   command = InfoCommand.new("path/to/fonts.ttc")
    #   info = command.run
    #   puts "Collection has #{info.num_fonts} fonts"
    class InfoCommand < BaseCommand
      # Extract information from font or collection.
      #
      # Auto-detects file type and returns appropriate model.
      #
      # @return [Models::FontInfo, Models::CollectionInfo] Metadata information
      def run
        if FontLoader.collection?(@font_path)
          collection_info
        else
          font_info
        end
      end

      private

      # Get collection information
      #
      # @return [Models::CollectionInfo, Models::CollectionBriefInfo] Collection metadata
      def collection_info
        collection = FontLoader.load_collection(@font_path)

        File.open(@font_path, "rb") do |io|
          if @options[:brief]
            # Brief mode: load each font and populate brief info
            brief_info = Models::CollectionBriefInfo.new
            brief_info.collection_path = @font_path
            brief_info.collection_type = collection.class.collection_format
            brief_info.collection_version = collection.version_string
            brief_info.num_fonts = collection.num_fonts
            brief_info.fonts = load_collection_fonts(collection, @font_path)

            brief_info
          else
            # Full mode: show detailed sharing statistics AND font information
            full_info = collection.collection_info(io, @font_path)

            # Add font information to full mode
            full_info.fonts = load_collection_fonts(collection, @font_path)

            full_info
          end
        end
      end

      # Load font information for all fonts in a collection
      #
      # @param collection [TrueTypeCollection, OpenTypeCollection] The collection
      # @param collection_path [String] Path to the collection file
      # @return [Array<Models::FontInfo>] Array of font info objects
      def load_collection_fonts(collection, collection_path)
        fonts = []

        collection.num_fonts.times do |index|
          # Load individual font from collection
          font = FontLoader.load(collection_path, font_index: index, mode: LoadingModes::METADATA)

          # Populate font info
          info = Models::FontInfo.new

          # Font format and variable status
          info.font_format = case font
                             when TrueTypeFont
                               "truetype"
                             when OpenTypeFont
                               "cff"
                             else
                               "unknown"
                             end
          info.is_variable = font.has_table?(Constants::FVAR_TAG)

          # Collection offset (only populated for fonts in collections)
          info.collection_offset = collection.font_offsets[index]

          # Essential names
          if font.has_table?(Constants::NAME_TAG)
            name_table = font.table(Constants::NAME_TAG)
            info.family_name = name_table.english_name(Tables::Name::FAMILY)
            info.subfamily_name = name_table.english_name(Tables::Name::SUBFAMILY)
            info.full_name = name_table.english_name(Tables::Name::FULL_NAME)
            info.postscript_name = name_table.english_name(Tables::Name::POSTSCRIPT_NAME)
            info.version = name_table.english_name(Tables::Name::VERSION)
          end

          # Essential metrics
          if font.has_table?(Constants::HEAD_TAG)
            head = font.table(Constants::HEAD_TAG)
            info.font_revision = head.font_revision
            info.units_per_em = head.units_per_em
          end

          # Vendor ID
          if font.has_table?(Constants::OS2_TAG)
            os2_table = font.table(Constants::OS2_TAG)
            info.vendor_id = os2_table.vendor_id
          end

          fonts << info
        end

        fonts
      end

      # Get individual font information
      #
      # @return [Models::FontInfo] Font metadata
      def font_info
        info = Models::FontInfo.new
        populate_font_format(info)

        # In brief mode, only populate essential fields for fast identification
        if @options[:brief]
          populate_brief_fields(info)
        else
          populate_full_fields(info)
        end

        info
      end

      # Populate font format and variable status based on font class and table presence.
      #
      # @param info [Models::FontInfo] FontInfo instance to populate
      def populate_font_format(info)
        # Determine base format from font class
        info.font_format = case font
                           when TrueTypeFont
                             "truetype"
                           when OpenTypeFont
                             "cff"
                           else
                             "unknown"
                           end

        # Check if variable font
        info.is_variable = font.has_table?(Constants::FVAR_TAG)
      end

      # Populate essential fields for brief mode (metadata tables only).
      #
      # Brief mode provides fast font identification by loading only 13 essential
      # attributes from metadata tables (name, head, OS/2). This is 5x faster than
      # full mode and optimized for font indexing systems.
      #
      # @param info [Models::FontInfo] FontInfo instance to populate
      def populate_brief_fields(info)
        # Essential names from name table
        if font.has_table?(Constants::NAME_TAG)
          name_table = font.table(Constants::NAME_TAG)
          info.family_name = name_table.english_name(Tables::Name::FAMILY)
          info.subfamily_name = name_table.english_name(Tables::Name::SUBFAMILY)
          info.full_name = name_table.english_name(Tables::Name::FULL_NAME)
          info.postscript_name = name_table.english_name(Tables::Name::POSTSCRIPT_NAME)
          info.version = name_table.english_name(Tables::Name::VERSION)
        end

        # Essential metrics from head table
        if font.has_table?(Constants::HEAD_TAG)
          head = font.table(Constants::HEAD_TAG)
          info.font_revision = head.font_revision
          info.units_per_em = head.units_per_em
        end

        # Vendor ID from OS/2 table
        if font.has_table?(Constants::OS2_TAG)
          os2_table = font.table(Constants::OS2_TAG)
          info.vendor_id = os2_table.vendor_id
        end
      end

      # Populate all fields for full mode.
      #
      # Full mode extracts comprehensive metadata from all available tables.
      #
      # @param info [Models::FontInfo] FontInfo instance to populate
      def populate_full_fields(info)
        populate_from_name_table(info) if font.has_table?(Constants::NAME_TAG)
        populate_from_os2_table(info) if font.has_table?(Constants::OS2_TAG)
        populate_from_head_table(info) if font.has_table?(Constants::HEAD_TAG)
        populate_color_info(info) if font.has_table?("COLR") && font.has_table?("CPAL")
        populate_svg_info(info) if font.has_table?("SVG ")
        populate_bitmap_info(info) if font.has_table?("CBLC") || font.has_table?("sbix")
      end

      # Populate FontInfo from the name table.
      #
      # @param info [Models::FontInfo] FontInfo instance to populate
      def populate_from_name_table(info)
        name_table = font.table(Constants::NAME_TAG)
        return unless name_table

        info.family_name = name_table.english_name(Tables::Name::FAMILY)
        info.subfamily_name = name_table.english_name(Tables::Name::SUBFAMILY)
        info.full_name = name_table.english_name(Tables::Name::FULL_NAME)
        info.postscript_name = name_table.english_name(Tables::Name::POSTSCRIPT_NAME)
        info.postscript_cid_name = name_table.english_name(Tables::Name::POSTSCRIPT_CID)
        info.preferred_family = name_table.english_name(Tables::Name::PREFERRED_FAMILY)
        info.preferred_subfamily = name_table.english_name(Tables::Name::PREFERRED_SUBFAMILY)
        info.mac_font_menu_name = name_table.english_name(Tables::Name::COMPATIBLE_FULL)
        info.version = name_table.english_name(Tables::Name::VERSION)
        info.unique_id = name_table.english_name(Tables::Name::UNIQUE_ID)
        info.description = name_table.english_name(Tables::Name::DESCRIPTION)
        info.designer = name_table.english_name(Tables::Name::DESIGNER)
        info.designer_url = name_table.english_name(Tables::Name::DESIGNER_URL)
        info.manufacturer = name_table.english_name(Tables::Name::MANUFACTURER)
        info.vendor_url = name_table.english_name(Tables::Name::VENDOR_URL)
        info.trademark = name_table.english_name(Tables::Name::TRADEMARK)
        info.copyright = name_table.english_name(Tables::Name::COPYRIGHT)
        info.license_description = name_table.english_name(Tables::Name::LICENSE_DESCRIPTION)
        info.license_url = name_table.english_name(Tables::Name::LICENSE_URL)
        info.sample_text = name_table.english_name(Tables::Name::SAMPLE_TEXT)
      end

      # Populate FontInfo from the OS/2 table.
      #
      # @param info [Models::FontInfo] FontInfo instance to populate
      def populate_from_os2_table(info)
        os2_table = font.table(Constants::OS2_TAG)
        return unless os2_table

        info.vendor_id = os2_table.vendor_id
        info.permissions = format_permissions(os2_table.type_flags)
      end

      # Populate FontInfo from the head table.
      #
      # @param info [Models::FontInfo] FontInfo instance to populate
      def populate_from_head_table(info)
        head_table = font.table(Constants::HEAD_TAG)
        return unless head_table

        info.font_revision = head_table.font_revision
        info.units_per_em = head_table.units_per_em
      end

      # Populate FontInfo with color font information from COLR/CPAL tables
      #
      # @param info [Models::FontInfo] FontInfo instance to populate
      def populate_color_info(info)
        colr_table = font.table("COLR")
        cpal_table = font.table("CPAL")

        return unless colr_table && cpal_table

        info.is_color_font = true
        info.color_glyphs = colr_table.num_color_glyphs
        info.color_palettes = cpal_table.num_palettes
        info.colors_per_palette = cpal_table.num_palette_entries
      rescue StandardError => e
        warn "Failed to populate color font info: #{e.message}"
        info.is_color_font = false
      end

      # Populate FontInfo with SVG table information
      #
      # @param info [Models::FontInfo] FontInfo instance to populate
      def populate_svg_info(info)
        svg_table = font.table("SVG ")

        return unless svg_table

        info.has_svg_table = true
        info.svg_glyph_count = svg_table.glyph_ids_with_svg.length
      rescue StandardError => e
        warn "Failed to populate SVG info: #{e.message}"
        info.has_svg_table = false
      end

      # Populate FontInfo with bitmap table information (CBDT/CBLC, sbix)
      #
      # @param info [Models::FontInfo] FontInfo instance to populate
      def populate_bitmap_info(info)
        bitmap_strikes = []
        ppem_sizes = []
        formats = []

        # Check for CBDT/CBLC (Google format)
        if font.has_table?("CBLC") && font.has_table?("CBDT")
          cblc = font.table("CBLC")
          info.has_bitmap_glyphs = true
          ppem_sizes.concat(cblc.ppem_sizes)

          cblc.strikes.each do |strike_rec|
            bitmap_strikes << Models::BitmapStrike.new(
              ppem: strike_rec.ppem,
              start_glyph_id: strike_rec.start_glyph_index,
              end_glyph_id: strike_rec.end_glyph_index,
              bit_depth: strike_rec.bit_depth,
              num_glyphs: strike_rec.glyph_range.size,
            )
          end
          formats << "PNG" # CBDT typically contains PNG data
        end

        # Check for sbix (Apple format)
        if font.has_table?("sbix")
          sbix = font.table("sbix")
          info.has_bitmap_glyphs = true
          ppem_sizes.concat(sbix.ppem_sizes)
          formats.concat(sbix.supported_formats)

          sbix.strikes.each do |strike|
            bitmap_strikes << Models::BitmapStrike.new(
              ppem: strike[:ppem],
              start_glyph_id: 0,
              end_glyph_id: strike[:num_glyphs] - 1,
              bit_depth: 32, # sbix is typically 32-bit
              num_glyphs: strike[:num_glyphs],
            )
          end
        end

        info.bitmap_strikes = bitmap_strikes unless bitmap_strikes.empty?
        info.bitmap_ppem_sizes = ppem_sizes.uniq.sort
        info.bitmap_formats = formats.uniq
      rescue StandardError => e
        warn "Failed to populate bitmap info: #{e.message}"
        info.has_bitmap_glyphs = false
      end

      # Format OS/2 embedding permission flags into a human-readable string.
      #
      # @param flags [Integer] OS/2 fsType flags
      # @return [String] Formatted permission string
      def format_permissions(flags)
        emb = flags & 15
        result = case emb
                 when 0 then "Installable"
                 when 2 then "Restricted License"
                 when 4 then "Preview & Print"
                 when 8 then "Editable"
                 else "Unknown (#{emb})"
                 end

        result += ", No subsetting" if flags.anybits?(0x100)
        result += ", Bitmap only" if flags.anybits?(0x200)
        result
      end
    end
  end
end
