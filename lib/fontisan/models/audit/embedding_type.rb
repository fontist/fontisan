# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Decoded OS/2 fsType bitfield → canonical embedding-permission string.
      #
      # Per OpenType spec, fsType is a bitfield. Only one of bits 0-3 should
      # be set (the basic permission level); bits 4-7 are modifiers that
      # only apply when INSTALLABLE (bit 3) is set.
      #
      # The decoder normalizes to one of seven canonical strings so
      # downstream consumers don't need to know the bit layout.
      class EmbeddingType < Lutaml::Model::Serializable
        # Bit masks (OpenType fsType bitfield).
        RESTRICTED_LICENSE_NO_EMBEDDING = 0x0001
        PREVIEW_AND_PRINT               = 0x0002
        EDITABLE_EMBEDDING              = 0x0004
        INSTALLABLE_EMBEDDING           = 0x0008
        NO_SUBSETTING                   = 0x0100
        BITMAP_EMBEDDING_ONLY           = 0x0200

        attribute :value, :string

        # Decoded canonical string for the given fsType bitfield.
        #
        # @param fs_type [Integer, nil] raw OS/2 fsType value
        # @return [String, nil] canonical permission name, or nil when
        #   fs_type is nil
        def self.decode(fs_type)
          return nil if fs_type.nil?

          if fs_type & RESTRICTED_LICENSE_NO_EMBEDDING != 0
            "restricted_license"
          elsif fs_type & PREVIEW_AND_PRINT != 0
            "preview_print"
          elsif fs_type & EDITABLE_EMBEDDING != 0
            "editable"
          elsif fs_type & INSTALLABLE_EMBEDDING != 0
            installable_subcategory(fs_type)
          elsif fs_type.zero?
            "installable"
          else
            "unknown"
          end
        end

        # Construct from a decoded canonical string.
        #
        # @param fs_type [Integer, nil]
        def self.from_fs_type(fs_type)
          new(value: decode(fs_type))
        end

        def to_s
          value
        end

        def self.installable_subcategory(fs_type)
          if fs_type & NO_SUBSETTING != 0 && fs_type & BITMAP_EMBEDDING_ONLY != 0
            "installable_no_subsetting_bitmap_only"
          elsif fs_type & NO_SUBSETTING != 0
            "installable_no_subsetting"
          elsif fs_type & BITMAP_EMBEDDING_ONLY != 0
            "installable_bitmap_only"
          else
            "installable"
          end
        end
        private_class_method :installable_subcategory
      end
    end
  end
end
