# frozen_string_literal: true

module Fontisan
  module Variation
    module Instancing
      # The design space of a variable font: fvar axes plus avar mapping.
      # Validates user coordinates and normalizes them to -1..1.
      class AxisSpace
        Axis = Struct.new(:tag, :minimum, :default, :maximum, :name_id)

        attr_reader :axes

        # @param fvar [String] raw fvar table
        # @param avar [String, nil] raw avar table
        def initialize(fvar, avar = nil)
          @axes = parse_fvar(fvar)
          @segments = avar ? parse_avar(avar) : {}
        end

        def tags
          @axes.map(&:tag)
        end

        # Named instances: [{ name_id:, coordinates: { tag => value } }]
        def self.named_instances(fvar)
          offset, axis_count, axis_size, inst_count, inst_size = header(fvar)
          base = offset + (axis_count * axis_size)
          Array.new(inst_count) do |i|
            pos = base + (i * inst_size)
            name_id = fvar[pos, 2].unpack1("n")
            coords = Array.new(axis_count) do |a|
              fixed(fvar, pos + 4 + (a * 4))
            end
            { name_id: name_id, values: coords }
          end
        end

        def self.header(fvar)
          offset, _res, axis_count, axis_size, inst_count, inst_size =
            fvar[4, 12].unpack("nnnnnn")
          [offset, axis_count, axis_size, inst_count, inst_size]
        end

        def self.fixed(data, pos)
          data[pos, 4].unpack1("l>") / 65536.0
        end

        # @param requested [Hash{String=>Numeric}] user coordinates
        # @return [Hash{String=>Float}] full user location (defaults filled)
        # @raise [InvalidCoordinatesError, InvalidAxisError]
        def validate(requested)
          known = tags
          requested.each_key do |tag|
            next if known.include?(tag.to_s)

            raise InvalidAxisError.new(
              axis: tag.to_s,
              reason: "font has axes #{known.join(', ')}",
            )
          end
          @axes.to_h do |axis|
            value = requested.transform_keys(&:to_s)[axis.tag]
            value = axis.default if value.nil?
            value = Float(value)
            unless value.finite? && value.between?(axis.minimum, axis.maximum)
              raise InvalidCoordinatesError.new(
                axis: axis.tag, value: value, range: [axis.minimum, axis.maximum],
              )
            end
            [axis.tag, value]
          end
        end

        # @return [Array<Float>] normalized (avar-mapped) coordinates, fvar order
        def normalize(location)
          @axes.map do |axis|
            value = location.fetch(axis.tag)
            n = if value < axis.default
                  (value - axis.default) / (axis.default - axis.minimum)
                elsif value > axis.default
                  (value - axis.default) / (axis.maximum - axis.default)
                else
                  0.0
                end
            map_segment(axis.tag, n.clamp(-1.0, 1.0))
          end
        end

        private

        def parse_fvar(fvar)
          offset, axis_count, axis_size, = self.class.header(fvar)
          Array.new(axis_count) do |i|
            pos = offset + (i * axis_size)
            Axis.new(fvar[pos, 4], self.class.fixed(fvar, pos + 4),
                     self.class.fixed(fvar, pos + 8),
                     self.class.fixed(fvar, pos + 12),
                     fvar[pos + 18, 2].unpack1("n"))
          end
        end

        # avar v1: per axis, array of [from, to] pairs (F2Dot14)
        def parse_avar(avar)
          axis_count = avar[6, 2].unpack1("n")
          pos = 8
          segments = {}
          axis_count.times do |i|
            count = avar[pos, 2].unpack1("n")
            pos += 2
            pairs = Array.new(count) do |j|
              from, to = avar[pos + (j * 4), 4].unpack("s>s>")
              [from / 16384.0, to / 16384.0]
            end
            pos += count * 4
            segments[@axes[i].tag] = pairs if @axes[i]
          end
          segments
        end

        def map_segment(tag, value)
          pairs = @segments[tag]
          return value if pairs.nil? || pairs.empty?

          exact = pairs.find { |from, _| from == value }
          return exact[1] if exact

          idx = pairs.index { |from, _| from > value }
          return value if idx.nil? || idx.zero?

          (f0, t0), (f1, t1) = pairs[idx - 1], pairs[idx]
          t0 + ((t1 - t0) * (value - f0) / (f1 - f0))
        end
      end
    end
  end
end
