# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Glyf + Loca are emitted together because loca is just an offset
      # index into glyf. This builder walks the subset's glyph mapping,
      # extracts each glyph's bytes (remapping composite component refs),
      # and produces the new glyf bytes, the new loca offsets, and the
      # union bounding box over the subset's glyphs.
      #
      # Extracted as a collaborator so both the Glyf and Loca strategies
      # can share a single build pass without coupling to each other or
      # to TableSubsetter internals.
      class GlyfLocaBuilder
        # @param font [SfntFont]
        # @param mapping [GlyphMapping]
        def initialize(font:, mapping:)
          @font = font
          @mapping = mapping
        end

        # @return [String] new glyf bytes
        attr_reader :glyf_data

        # @return [Array<Integer>] loca offsets (one per glyph + 1)
        attr_reader :loca_offsets

        # @return [Array(Integer, Integer, Integer, Integer), nil] union
        #   bbox as [x_min, y_min, x_max, y_max], or nil if all glyphs empty
        attr_reader :bbox

        # Build glyf + loca + bbox. Idempotent — re-calling is a no-op.
        #
        # @return [self]
        def build
          return self if @glyf_data

          glyf = @font.table("glyf")
          loca = @font.table("loca")
          head = @font.table("head")

          ensure_loca_parsed!(loca, head)

          @glyf_data = String.new(encoding: Encoding::BINARY)
          @loca_offsets = []
          current_offset = 0

          bbox_x_min = 1 << 30
          bbox_y_min = 1 << 30
          bbox_x_max = -(1 << 30)
          bbox_y_max = -(1 << 30)

          @mapping.old_ids.each do |old_id|
            @loca_offsets << current_offset

            offset = loca.offset_for(old_id)
            size = loca.size_of(old_id)
            next if size.nil? || size.zero?

            glyph_data = glyf.raw_data[offset, size]

            if glyph_data.bytesize >= 10
              _n, gx_min, gy_min, gx_max, gy_max = glyph_data[0,
                                                              10].unpack("n5")
              gx_min = to_signed_16(gx_min)
              gy_min = to_signed_16(gy_min)
              gx_max = to_signed_16(gx_max)
              gy_max = to_signed_16(gy_max)
              bbox_x_min = gx_min if gx_min < bbox_x_min
              bbox_y_min = gy_min if gy_min < bbox_y_min
              bbox_x_max = gx_max if gx_max > bbox_x_max
              bbox_y_max = gy_max if gy_max > bbox_y_max
            end

            glyph_data = remap_compound!(glyph_data) if compound?(glyph_data)

            @glyf_data << glyph_data
            current_offset += glyph_data.bytesize
          end

          @loca_offsets << current_offset

          return if bbox_x_min > bbox_x_max

          @bbox = [bbox_x_min, bbox_y_min, bbox_x_max, bbox_y_max]
          self
        end

        private

        def ensure_loca_parsed!(loca, head)
          return if loca.parsed?

          maxp = @font.table("maxp")
          loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)
        end

        def compound?(data)
          return false if data.length < 2

          num_contours = to_signed_16(data[0, 2].unpack1("n"))
          num_contours == -1
        end

        def remap_compound!(data)
          new_data = data.dup
          offset = 10 # skip 10-byte header

          loop do
            break if offset >= new_data.length - 4

            flags = new_data[offset, 2].unpack1("n")
            old_glyph_index = new_data[offset + 2, 2].unpack1("n")

            new_glyph_index = @mapping.new_id(old_glyph_index)
            unless new_glyph_index
              raise Fontisan::SubsettingError,
                    "Component glyph #{old_glyph_index} not in subset"
            end

            new_data[offset + 2, 2] = [new_glyph_index].pack("n")
            offset += 4 # flags + glyph_index
            offset += (flags & 0x0001).zero? ? 2 : 4 # args

            if (flags & 0x0080) != 0
              offset += 8 # 2x2 matrix
            elsif (flags & 0x0040) != 0
              offset += 4 # X and Y scale
            elsif (flags & 0x0008) != 0
              offset += 2 # uniform scale
            end

            break unless (flags & 0x0020) != 0 # MORE_COMPONENTS
          end

          new_data
        end

        def to_signed_16(value)
          value > 0x7FFF ? value - 0x10000 : value
        end
      end
    end
  end
end
