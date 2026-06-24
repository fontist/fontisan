# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Decoded OS/2 fsSelection bitfield → sorted array of flag names.
      #
      # Per OpenType spec, fsSelection is a bitfield with these bits:
      #
      #   bit 0 (0x001): italic
      #   bit 1 (0x002): underscore
      #   bit 2 (0x004): negative
      #   bit 3 (0x008): outlined
      #   bit 4 (0x010): strikeout
      #   bit 5 (0x020): bold
      #   bit 6 (0x040): regular
      #   bit 7 (0x080): use_typo_metrics
      #   bit 8 (0x100): wws
      #   bit 9 (0x200): oblique
      #
      # Returns names in spec order (bit ascending).
      class FsSelectionFlags < Lutaml::Model::Serializable
        FLAGS = {
          0x001 => "italic",
          0x002 => "underscore",
          0x004 => "negative",
          0x008 => "outlined",
          0x010 => "strikeout",
          0x020 => "bold",
          0x040 => "regular",
          0x080 => "use_typo_metrics",
          0x100 => "wws",
          0x200 => "oblique",
        }.freeze

        attribute :flags, :string, collection: true

        # Decoded array of flag names in spec order (bit ascending).
        #
        # @param fs_selection [Integer, nil] raw OS/2 fsSelection value
        # @return [Array<String>, nil]
        def self.decode(fs_selection)
          return nil if fs_selection.nil?

          FLAGS.each_with_object([]) do |(mask, name), acc|
            acc << name if fs_selection & mask != 0
          end
        end

        # Construct from a raw fsSelection value.
        #
        # @param fs_selection [Integer, nil]
        def self.from_fs_selection(fs_selection)
          new(flags: decode(fs_selection))
        end
      end
    end
  end
end
