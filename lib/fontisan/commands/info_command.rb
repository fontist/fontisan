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
      # @return [Models::CollectionInfo] Collection metadata
      def collection_info
        collection = FontLoader.load_collection(@font_path)

        File.open(@font_path, "rb") do |io|
          collection.collection_info(io, @font_path)
        end
      end

      # Get individual font information
      #
      # @return [Models::FontInfo] Font metadata
      def font_info
        info = Models::FontInfo.new
        populate_font_format(info)
        populate_from_name_table(info) if font.has_table?(Constants::NAME_TAG)
        populate_from_os2_table(info) if font.has_table?(Constants::OS2_TAG)
        populate_from_head_table(info) if font.has_table?(Constants::HEAD_TAG)
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
