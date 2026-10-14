# frozen_string_literal: true

require "fontisan"

module Fontisan
  module Tables
    class Gpos
      # Checked views share physical identity without copying table suffixes.
      class BinaryView
        def initialize(data, offset: 0, cache: {})
          @data = data
          @offset = offset
          @cache = cache
        end

        def bytes(offset, length)
          if offset.negative? || length.negative? || @offset + offset + length > @data.bytesize
            raise ParseError, "Truncated GPOS data at byte #{offset}"
          end

          @data.byteslice(@offset + offset, length)
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
          self.class.new(@data, offset: @offset + offset, cache: @cache)
        end

        def record(type, header:, count_offset:, item_size:)
          bytes(0, header + uint16(count_offset) * item_size)
          type.read(@data.byteslice(@offset..))
        end

        def cached(context)
          key = [@offset, context]
          @cache.fetch(key) { @cache[key] = yield }
        end

        def freeze
          @cache.freeze
          super
        end
      end

      # Coverage ranges remain compact, including the full glyph-ID domain.
      class Coverage
        include Enumerable

        attr_reader :size

        def initialize(view)
          format = view.uint16(0)
          count = view.uint16(2)
          case format
          when 1
            @glyphs = view.array(4, count).freeze
            unless @glyphs.each_cons(2).all? { |first, second| first < second }
              raise ParseError, "Unsorted or duplicate GPOS glyph IDs"
            end

            @size = count
          when 2
            @ranges = view.array(4, count * 3).each_slice(3).map(&:freeze).freeze
            @size = 0
            previous = -1
            @ranges.each do |first, last, index|
              if first > last || index != @size || first <= previous
                raise ParseError, "Invalid GPOS coverage range"
              end

              @size += last - first + 1
              previous = last
            end
          else
            raise ParseError, "Unsupported Coverage format #{format}"
          end
          freeze
        end

        def include?(glyph)
          return @glyphs.bsearch { |candidate| candidate >= glyph } == glyph if @glyphs

          record = @ranges.bsearch { |_first, last, _index| last >= glyph }
          record && record[0] <= glyph
        end

        def each(&block)
          return enum_for(:each) unless block

          if @glyphs
            @glyphs.each(&block)
          else
            @ranges.each do |first, last, _index|
              (first..last).each(&block)
            end
          end
          self
        end
      end

      # Class arrays support direct glyph indexing without singleton ranges.
      class ClassDefinition
        attr_reader :maximum

        def initialize(view)
          @view = view
          case view.uint16(0)
          when 1
            @first = view.uint16(2)
            @count = view.uint16(4)
            raise ParseError, "Invalid GPOS class definition" if @first + @count > 65536

            @maximum = view.array(6, @count).max || 0
          when 2
            @ranges = view.array(4, view.uint16(2) * 3).each_slice(3).map(&:freeze).freeze
            previous = -1
            @maximum = 0
            @ranges.each do |first, last, value|
              if first <= previous || first > last
                raise ParseError, "Invalid GPOS class definition"
              end

              @maximum = [@maximum, value].max
              previous = last
            end
          else
            raise ParseError, "Unsupported ClassDef format #{view.uint16(0)}"
          end
          freeze
        end

        def [](glyph)
          if @ranges
            record = @ranges.bsearch { |_first, last, _value| last >= glyph }
            record && record[0] <= glyph ? record[2] : 0
          else
            index = glyph - @first
            index.between?(0, @count - 1) ? @view.uint16(6 + index * 2) : 0
          end
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
          @second_format = view.uint16(6)
          @first_size = value_size(@first_format)
          @record_size = @first_size + value_size(@second_format)
          @advance_offset = value_size(@first_format & 3)
          @coverage = coverage
          @left_glyphs = @coverage
          @format == 1 ? parse_pairs : parse_classes
          freeze
        end

        def class_based?
          @format == 2
        end

        def covers?(glyph)
          @coverage.include?(glyph)
        end

        def adjustment(left, right)
          return unless covers?(left)
          return @pairs.fetch(left)[right] unless class_based?

          row = @first_classes[left]
          column = @second_classes[right]
          advance(@matrix, (row * @second_count + column) * @record_size)
        end

        def right_glyphs(left, glyph_count)
          class_based? ? (0...glyph_count) : @pairs.fetch(left).each_key
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
          view.cached(:coverage) { Coverage.new(view) }
        end

        def parse_pairs
          count = @view.uint16(8)
          raise ParseError, "GPOS PairSet count differs from coverage" unless count == left_glyphs.size

          offsets = @view.array(10, count)
          @pairs = {}
          left_glyphs.each_with_index do |left, index|
            view = @view.child(offsets[index], minimum: 10 + count * 2)
            @pairs[left] = view.cached([:pair_set, @first_format, @second_format]) { pair_set(view) }
          end
          @pairs.freeze
        end

        def pair_set(view)
          count = view.uint16(0)
          view.bytes(2, count * (2 + @record_size))
          previous = -1
          pairs = {}
          count.times do |index|
            start = 2 + index * (2 + @record_size)
            glyph = view.uint16(start)
            raise ParseError, "Unsorted or duplicate GPOS glyph IDs" if glyph <= previous

            pairs[glyph] = advance(view, start + 2)
            previous = glyph
          end
          pairs.freeze
        end

        def matrix_size
          @view.uint16(12) * @view.uint16(14) * @record_size
        end

        def parse_classes
          first_count = @view.uint16(12)
          @second_count = @view.uint16(14)
          raise ParseError, "Empty GPOS class matrix" if first_count.zero? || @second_count.zero?

          @matrix = BinaryView.new(@view.bytes(16, matrix_size).freeze).freeze
          @first_classes = class_definition(@view.uint16(8), first_count)
          @second_classes = class_definition(@view.uint16(10), @second_count)
        end

        def class_definition(offset, class_count)
          view = @view.child(offset, minimum: 16 + matrix_size)
          definition = view.cached(:class_definition) { ClassDefinition.new(view) }
          raise ParseError, "Invalid GPOS class definition" if definition.maximum >= class_count

          definition
        end
      end

      private_constant :BinaryView, :Coverage, :ClassDefinition, :PairPosition
    end
  end
end
