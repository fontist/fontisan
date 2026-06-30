# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `avar` (Axis Variation) table.
      #
      # avar defines non-linear interpolation curves for each axis.
      # For axes with linear interpolation (the common case), each
      # axis gets 3 default maps: (-1→-1, 0→0, 1→1).
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/avar
      module Avar
        # @param axes [Array<Hash>] axis definitions (tag + optional maps)
        # @return [String] avar table bytes
        def self.build(axes:)
          return nil if axes.nil? || axes.empty?

          io = +""
          io << [0x00010000].pack("N") # version 1.0
          io << [0].pack("n")          # reserved
          io << [axes.size].pack("n")  # axisCount

          axes.each do |axis|
            maps = axis[:maps] || default_maps
            io << [maps.size].pack("n")
            maps.each do |from, to|
              io << [f2dot14(from), f2dot14(to)].pack("nn")
            end
          end

          io
        end

        def self.default_maps
          [[-1.0, -1.0], [0.0, 0.0], [1.0, 1.0]].freeze
        end

        def self.f2dot14(value)
          (value.to_f * 16384).to_i.clamp(-16384, 16384)
        end
        private_class_method :default_maps, :f2dot14
      end
    end
  end
end
