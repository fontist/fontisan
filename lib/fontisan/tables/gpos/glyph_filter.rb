# frozen_string_literal: true

require "fontisan/tables/gpos/pair_position"

module Fontisan
  module Tables
    class Gpos
      # Evaluates lookup flags against explicit GDEF classes for pair endpoints.
      class GlyphFilter
        def initialize(flags, gdef, mark_set:)
          raise ParseError, "Reserved GPOS lookup flags" unless (flags & 0x00e0).zero?

          @flags = flags
          if (flags & 0xff1e).positive?
            unless gdef
              raise UnsupportedFormatError, "GPOS lookup filtering requires gdef: font.table_data['GDEF']"
            end

            @gdef = gdef
            @header = header
            @classes = definition(@header[1], "glyph classes")
            raise ParseError, "Invalid GDEF glyph class" if @classes.maximum > 4

            if (flags & 8).zero?
              if (flags & 16).positive?
                @mark_set = mark_set(mark_set)
              elsif (flags >> 8).positive?
                @mark_classes = definition(@header[2], "mark attachment classes")
              end
            end
          end
          freeze
        end

        def allows?(glyph)
          return true unless @classes

          glyph_class = @classes[glyph]
          return false if glyph_class.between?(1, 3) && (@flags & (1 << glyph_class)).positive?
          return true unless glyph_class == 3
          return @mark_set.include?(glyph) if @mark_set
          return @mark_classes[glyph] == (@flags >> 8) if @mark_classes

          true
        end

        private

        def header
          @gdef.cached(:gdef_header) do
            minor = @gdef.uint16(2)
            unless @gdef.uint16(0) == 1 && [0, 2, 3].include?(minor)
              raise ParseError, "Unsupported GDEF version"
            end

            length = { 0 => 12, 2 => 14, 3 => 18 }.fetch(minor)
            @gdef.bytes(0, length)
            [length, @gdef.uint16(4), @gdef.uint16(10), minor.zero? ? 0 : @gdef.uint16(12)].freeze
          end
        end

        def definition(offset, name)
          raise UnsupportedFormatError, "GPOS filtering requires GDEF #{name}" if offset.zero?

          view = @gdef.child(offset, minimum: @header[0])
          view.cached(:class_definition) { ClassDefinition.new(view) }
        end

        def mark_set(index)
          raise UnsupportedFormatError, "GPOS filtering requires GDEF mark glyph sets" if @header[3].zero?

          sets = @gdef.child(@header[3], minimum: @header[0])
          raise ParseError, "Unsupported GDEF mark glyph sets format" unless sets.uint16(0) == 1

          count = sets.uint16(2)
          raise ParseError, "Invalid GDEF mark filtering set #{index}" if index >= count

          sets.uint32(4 + (count - 1) * 4)
          view = sets.child(sets.uint32(4 + index * 4), minimum: 4 + count * 4)
          view.cached(:coverage) { Coverage.new(view) }
        end
      end

      private_constant :GlyphFilter
    end
  end
end
