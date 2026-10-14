# frozen_string_literal: true

module Fontisan
  module Tables
    class Gpos
      # Checked spans shared by the layout selector and PairPos parser.
      class BinaryView
        def initialize(data)
          @data = data
        end

        def bytes(offset, length)
          if offset.negative? || length.negative? || offset + length > @data.bytesize
            raise ParseError, "Truncated GPOS data at byte #{offset}"
          end

          @data.byteslice(offset, length)
        end

        def uint16(offset)
          bytes(offset, 2).unpack1("n")
        end

        def array(offset, count)
          bytes(offset, count * 2).unpack("n*")
        end

        def child(offset, minimum:)
          raise ParseError, "Invalid GPOS offset #{offset}" if offset < minimum

          bytes(offset, 1)
          self.class.new(@data.byteslice(offset..))
        end

        def record(type, header:, count_offset:, item_size:)
          bytes(0, header + uint16(count_offset) * item_size)
          type.read(@data)
        end
      end

      # Compact PairPos data; class matrices stay in their binary representation.
      class PairPosition
        attr_reader :left_glyphs

        def initialize(view)
          @view = view
          @format = view.uint16(0)
          raise ParseError, "Unsupported PairPos format #{@format}" unless [1, 2].include?(@format)

          @first_format = view.uint16(4)
          @first_size = value_size(@first_format)
          @record_size = @first_size + value_size(view.uint16(6))
          @advance_offset = value_size(@first_format & 3)
          @left_glyphs = coverage
          @format == 1 ? parse_pairs : parse_classes
        end

        def class_based?
          @format == 2
        end

        def adjustment(left, right)
          return unless @coverage.include?(left)
          return @pairs.fetch(left)[right] unless class_based?

          row = glyph_class(@first_classes, left)
          column = glyph_class(@second_classes, right)
          advance(@matrix, (row * @second_count + column) * @record_size)
        end

        def right_glyphs(left, glyph_count)
          class_based? ? (0...glyph_count) : @pairs.fetch(left).keys
        end

        private

        def value_size(format)
          raise ParseError, "Reserved GPOS ValueFormat bits" unless (format & 0xff00).zero?

          format.digits(2).sum * 2
        end

        def advance(view, offset)
          return 0 if (@first_format & 4).zero?

          value = view.uint16(offset + @advance_offset)
          value >= 0x8000 ? value - 0x10000 : value
        end

        def coverage
          minimum = @format == 1 ? 10 + @view.uint16(8) * 2 : 16 + matrix_size
          view = @view.child(@view.uint16(2), minimum: minimum)
          format = view.uint16(0)
          count = view.uint16(2)
          glyphs = case format
                   when 1 then view.array(4, count)
                   when 2 then coverage_ranges(view, count)
                   else raise ParseError, "Unsupported Coverage format #{format}"
                   end
          validate_glyph_order(glyphs)
          @coverage = glyphs.to_h { |gid| [gid, true] }
          glyphs
        end

        def coverage_ranges(view, count)
          records = view.array(4, count * 3).each_slice(3)
          records.each_with_object([]) do |(first, last, index), glyphs|
            if first > last || index != glyphs.size || (!glyphs.empty? && first <= glyphs.last)
              raise ParseError, "Invalid GPOS coverage range"
            end

            glyphs.concat((first..last).to_a)
          end
        end

        def validate_glyph_order(glyphs)
          return if glyphs.each_cons(2).all? { |first, second| first < second }

          raise ParseError, "Unsorted or duplicate GPOS glyph IDs"
        end

        def parse_pairs
          count = @view.uint16(8)
          raise ParseError, "GPOS PairSet count differs from coverage" unless count == left_glyphs.size

          offsets = @view.array(10, count)
          @pairs = left_glyphs.zip(offsets).to_h do |left, offset|
            view = @view.child(offset, minimum: 10 + count * 2)
            pair_count = view.uint16(0)
            view.bytes(2, pair_count * (2 + @record_size))
            records = Array.new(pair_count) do |index|
              start = 2 + index * (2 + @record_size)
              [view.uint16(start), advance(view, start + 2)]
            end
            validate_glyph_order(records.map(&:first))
            [left, records.to_h]
          end
        end

        def matrix_size
          @view.uint16(12) * @view.uint16(14) * @record_size
        end

        def parse_classes
          first_count = @view.uint16(12)
          @second_count = @view.uint16(14)
          raise ParseError, "Empty GPOS class matrix" if first_count.zero? || @second_count.zero?

          @matrix = BinaryView.new(@view.bytes(16, matrix_size))
          @first_classes = class_definition(@view.uint16(8), first_count)
          @second_classes = class_definition(@view.uint16(10), @second_count)
        end

        def class_definition(offset, class_count)
          view = @view.child(offset, minimum: 16 + matrix_size)
          format = view.uint16(0)
          records = case format
                    when 1 then class_array(view)
                    when 2 then view.array(4, view.uint16(2) * 3).each_slice(3).to_a
                    else raise ParseError, "Unsupported ClassDef format #{format}"
                    end
          previous = -1
          records.each do |first, last, value|
            if first <= previous || first > last || last > 65535 || value >= class_count
              raise ParseError, "Invalid GPOS class definition"
            end

            previous = last
          end
          records
        end

        def class_array(view)
          first = view.uint16(2)
          view.array(6, view.uint16(4)).each_with_index.map do |value, index|
            [first + index, first + index, value]
          end
        end

        def glyph_class(records, glyph)
          record = records.bsearch { |_first, last, _value| last >= glyph }
          record && record[0] <= glyph ? record[2] : 0
        end
      end

      private_constant :BinaryView, :PairPosition
    end
  end
end
