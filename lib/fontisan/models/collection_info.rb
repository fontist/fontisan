# frozen_string_literal: true

require "lutaml/model"
require_relative "table_sharing_info"
require_relative "font_info"

module Fontisan
  module Models
    # Model for collection metadata
    #
    # Represents comprehensive information about a TTC/OTC collection.
    # Used by InfoCommand when operating on collection files.
    #
    # @example Creating collection info
    #   info = CollectionInfo.new(
    #     collection_path: "fonts.ttc",
    #     collection_format: "TTC",
    #     ttc_tag: "ttcf",
    #     major_version: 2,
    #     minor_version: 0,
    #     num_fonts: 6,
    #     font_offsets: [48, 380, 712, 1044, 1376, 1676],
    #     file_size_bytes: 2240000,
    #     table_sharing: table_sharing_obj,
    #     fonts: [font_info1, font_info2, ...]
    #   )
    class CollectionInfo < Lutaml::Model::Serializable
      attribute :collection_path, :string
      attribute :collection_format, :string
      attribute :ttc_tag, :string
      attribute :major_version, :integer
      attribute :minor_version, :integer
      attribute :num_fonts, :integer
      attribute :font_offsets, :integer, collection: true
      attribute :file_size_bytes, :integer
      attribute :table_sharing, TableSharingInfo
      attribute :fonts, FontInfo, collection: true

      yaml do
        map "collection_path", to: :collection_path
        map "collection_format", to: :collection_format
        map "ttc_tag", to: :ttc_tag
        map "major_version", to: :major_version
        map "minor_version", to: :minor_version
        map "num_fonts", to: :num_fonts
        map "font_offsets", to: :font_offsets
        map "file_size_bytes", to: :file_size_bytes
        map "table_sharing", to: :table_sharing
        map "fonts", to: :fonts
      end

      json do
        map "collection_path", to: :collection_path
        map "collection_format", to: :collection_format
        map "ttc_tag", to: :ttc_tag
        map "major_version", to: :major_version
        map "minor_version", to: :minor_version
        map "num_fonts", to: :num_fonts
        map "font_offsets", to: :font_offsets
        map "file_size_bytes", to: :file_size_bytes
        map "table_sharing", to: :table_sharing
        map "fonts", to: :fonts
      end

      # Get version as a formatted string
      #
      # @return [String] Version string (e.g., "2.0")
      def version_string
        "#{major_version}.#{minor_version}"
      end

      # Get version as a hexadecimal string
      #
      # @return [String] Hex version (e.g., "0x00020000")
      def version_hex
        version_int = (major_version << 16) | minor_version
        format("0x%08X", version_int)
      end
    end
  end
end
