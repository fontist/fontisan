# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the TrueType `glyf` + `loca` tables. Each glyph's
      # outline is delta-encoded into the glyf table; loca is the
      # offset index.
      #
      # For OTF output this module is NOT used — CFF takes its place.
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/glyf
      module GlyfLoca
        # Flag bits (simple glyph)
        FLAG_ON_CURVE       = 0x01
        FLAG_X_SHORT        = 0x02
        FLAG_Y_SHORT        = 0x04
        FLAG_REPEAT         = 0x08
        FLAG_X_IS_POSITIVE  = 0x10 # only meaningful if FLAG_X_SHORT
        FLAG_Y_IS_POSITIVE  = 0x20 # only meaningful if FLAG_Y_SHORT
        FLAG_OVERLAP_SIMPLE = 0x40

        # @param _font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] in gid order
        # @return [Hash<String, String>] {"glyf" => bytes, "loca" => bytes}
        def self.build(_font, glyphs:)
          glyf_bytes = +""
          offsets = [0]

          glyphs.each do |glyph|
            glyf_bytes << encode_glyph(glyph)
            glyf_bytes << "\x00" while glyf_bytes.bytesize.odd? # 2-byte align
            offsets << glyf_bytes.bytesize
          end

          # Choose loca format based on the largest offset.
          use_long = offsets.max > 0x1FFFE # 2 × uint16 max
          loca_bytes =
            if use_long
              offsets.pack("N*")
            else
              offsets.map { |o| o / 2 }.pack("n*")
            end

          { "glyf" => glyf_bytes, "loca" => loca_bytes, :loca_format => use_long ? 1 : 0 }
        end

        # Encode a single glyph into glyf bytes. Empty glyphs (no
        # contours, no components) produce zero bytes per spec.
        def self.encode_glyph(glyph)
          return "" if glyph.contours.empty? && glyph.components.empty?
          return encode_composite(glyph) if glyph.composite?

          encode_simple(glyph)
        end

        # Encode a simple (non-composite) glyph.
        def self.encode_simple(glyph)
          bbox = glyph.bbox
          header = [
            glyph.contours.size, # numberOfContours (int16)
            bbox.x_min.to_i, bbox.y_min.to_i,
            bbox.x_max.to_i, bbox.y_max.to_i
          ].pack("nnnnn")
          # NB: pack 'n' for int16 truncates negatives to unsigned 16-bit
          # two's complement — which is what OpenType wants.

          # endPtsOfContours (uint16[numContours])
          end_points = +""
          point_count = 0
          glyph.contours.each do |contour|
            point_count += contour.points.size
            end_points << [point_count - 1].pack("n")
          end

          # instructions: empty for MVP
          instructions = [0].pack("n")

          flags, x_bytes, y_bytes = encode_points(glyph.contours)

          header + end_points + instructions + flags + x_bytes + y_bytes
        end

        # Encode all points across contours into (flags, x_bytes, y_bytes).
        def self.encode_points(contours)
          flags = +""
          x_bytes = +""
          y_bytes = +""

          prev_x = 0
          prev_y = 0
          contours.flat_map(&:points).each do |point|
            dx = point.x.to_i - prev_x
            dy = point.y.to_i - prev_y

            flag = point.on_curve? ? FLAG_ON_CURVE : 0

            # X coordinate
            if dx.zero?
              # No X flag — coordinate omitted
            elsif dx.between?(-255, 255)
              flag |= FLAG_X_SHORT
              flag |= FLAG_X_IS_POSITIVE if dx.positive?
              x_bytes << [dx.abs].pack("C")
            else
              x_bytes << [dx & 0xFFFF].pack("n")
            end

            # Y coordinate
            if dy.zero?
              # No Y flag
            elsif dy.between?(-255, 255)
              flag |= FLAG_Y_SHORT
              flag |= FLAG_Y_IS_POSITIVE if dy.positive?
              y_bytes << [dy.abs].pack("C")
            else
              y_bytes << [dy & 0xFFFF].pack("n")
            end

            flags << [flag].pack("C")
            prev_x = point.x.to_i
            prev_y = point.y.to_i
          end

          [flags, x_bytes, y_bytes]
        end

        # Composite glyph encoding (component references with optional
        # transformations). Out of scope for MVP — emits empty bytes.
        def self.encode_composite(_glyph)
          # TODO.full/07: implement composite glyph encoding when the
          # spec needs it. For now, return empty (the glyph renders as
          # nothing).
          ""
        end
        private_class_method :encode_glyph, :encode_simple, :encode_points, :encode_composite
      end
    end
  end
end
