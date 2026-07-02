# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `CPAL` (Color Palette) table.
      #
      # CPAL stores one or more palettes of BGRA color records,
      # referenced by COLR layers and other color-glyph mechanisms.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cpal
      module Cpal
        VERSION = 0
        HEADER_SIZE = 12
        COLOR_RECORD_SIZE = 4 # BGRA

        # Color value object: BGRA uint8 tuple.
        Color = Struct.new(:blue, :green, :red, :alpha, keyword_init: true) do
          def to_bytes
            [blue || 0, green || 0, red || 0, alpha || 255].pack("C4")
          end
        end

        # @param palettes [Array<Array<Color>>] one or more palettes,
        #   each an array of Color values. All palettes must have the
        #   same number of entries.
        # @return [String, nil] CPAL table bytes, or nil if no palettes
        def self.build(palettes:)
          return nil if palettes.nil? || palettes.empty?

          num_entries = palettes.first.size
          num_palettes = palettes.size
          num_records = num_entries * num_palettes

          indices = Array.new(num_palettes) { |i| i * num_entries }
          records = palettes.flatten

          offset = HEADER_SIZE + (num_palettes * 2) # header + indices

          io = +""
          io << [VERSION, num_entries, num_palettes, num_records, offset].pack("nnnnN")
          indices.each { |idx| io << [idx].pack("n") }
          records.each { |c| io << color_bytes(c) }
          io
        end

        def self.color_bytes(color)
          return color.to_bytes if color.is_a?(Color)

          b = color[:blue] || color["blue"] || 0
          g = color[:green] || color["green"] || 0
          r = color[:red] || color["red"] || 0
          a = color[:alpha] || color["alpha"] || 255
          [b, g, r, a].pack("C4")
        end

        private_class_method :color_bytes
      end
    end
  end
end
