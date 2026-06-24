# frozen_string_literal: true

module Fontisan
  module Audit
    # Extracts style descriptors from a loaded font's OS/2, head, and fvar
    # tables. One extractor per font; cheap to construct.
    #
    # All fields return nil when the underlying table is absent or the
    # value is unset (e.g., Type 1 fonts have no OS/2). Callers must
    # tolerate nils.
    #
    # Duck typing: uses only `font.has_table?(tag)` and `font.table(tag)`.
    # No class-specific branching — any object that honors the SFNT
    # contract works (TrueTypeFont, OpenTypeFont, WoffFont, Woff2Font,
    # and individual faces from collections).
    class StyleExtractor
      FS_SELECTION_ITALIC_BIT = 0
      MAC_STYLE_BOLD_BIT      = 0
      private_constant :FS_SELECTION_ITALIC_BIT, :MAC_STYLE_BOLD_BIT

      # @param font [Object] an SFNT-compatible font object
      def initialize(font)
        @font = font
      end

      def weight_class
        os2&.us_weight_class&.to_i
      end

      def width_class
        os2&.us_width_class&.to_i
      end

      # OS/2.fsSelection bit 0 (ITALIC).
      def italic
        return nil unless os2

        (os2.fs_selection.to_i & (1 << FS_SELECTION_ITALIC_BIT)).nonzero?
      end

      # head.macStyle bit 0 (BOLD). Per OpenType convention, bold is read
      # from head, not OS/2.
      def bold
        return nil unless head

        (head.mac_style.to_i & (1 << MAC_STYLE_BOLD_BIT)).nonzero?
      end

      # OS/2.panose as a space-joined 10-digit string, e.g. "2 0 5 3 0 0 0 0 0 0".
      # Returns nil if there is no OS/2 table.
      def panose
        bytes = os2&.panose
        return nil if bytes.nil?

        bytes = bytes.to_a
        return nil if bytes.empty?

        bytes.join(" ")
      end

      def variable?
        @font.has_table?("fvar")
      end

      # @return [Array<Models::Audit::AuditAxis>]
      def axes
        return [] unless variable?

        fvar = @font.table("fvar")
        return [] unless fvar&.axes

        fvar.axes.map do |axis|
          Models::Audit::AuditAxis.new(
            tag: axis.axis_tag,
            min_value: axis.min_value,
            default_value: axis.default_value,
            max_value: axis.max_value,
            name: lookup_axis_name(axis.axis_name_id),
          )
        end
      end

      private

      def os2
        return @os2 if defined?(@os2)

        @os2 = @font.has_table?("OS/2") ? @font.table("OS/2") : nil
      end

      def head
        return @head if defined?(@head)

        @head = @font.has_table?("head") ? @font.table("head") : nil
      end

      def lookup_axis_name(name_id)
        return nil unless name_id && @font.has_table?("name")

        name = @font.table("name")
        name.english_name(name_id)
      end
    end
  end
end
