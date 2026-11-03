# frozen_string_literal: true

module Fontisan
  module Variation
    module Instancing
      # Produces a static TrueType font from a gvar-based variable font by
      # applying gvar deltas (with IUP for untouched points) to glyf, HVAR or
      # phantom-point deltas to hmtx, and updating OS/2 and name for the
      # chosen location. cvar, GPOS/GDEF variations and MVAR are not applied.
      class TrueTypeInstancer
        DROPPED = %w[fvar gvar avar HVAR VVAR MVAR STAT cvar DSIG].freeze
        WIDTH_CLASSES = [50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200].freeze

        # @param tables [Hash{String=>String}] raw tables of the variable font
        # @param coordinates [Hash{String=>Numeric}] axis tag => user value
        def initialize(tables, coordinates)
          @tables = tables
          @coordinates = coordinates
          check_font!
          @space = AxisSpace.new(tables["fvar"], tables["avar"])
          @location = @space.validate(coordinates)
          @norm = @space.normalize(@location)
        end

        # @return [Hash{String=>String}] raw tables of the static instance
        def call
          num_glyphs = @tables["maxp"][4, 2].unpack1("n")
          read_metrics(num_glyphs)
          glyphs = Array.new(num_glyphs) { |gid| instance_glyph(gid) }
          resolve_bounds(glyphs)
          out = @tables.except(*DROPPED)
          write_glyf_loca(out, glyphs)
          write_hmtx(out, glyphs)
          update_head_hhea(out, glyphs)
          update_os2(out)
          update_name(out)
          out
        end

        private

        Glyph = Struct.new(:outline, :points, :advance, :bbox, :data)

        def check_font!
          unless @tables["fvar"]
            raise MissingVariationTableError.new(table: "fvar")
          end
          return if @tables["gvar"] && @tables["glyf"]

          raise MissingVariationTableError.new(
            table: "gvar",
            message: "Static instancing needs TrueType outlines with gvar " \
                     "(CFF2 variable fonts are not supported yet)",
          )
        end

        def read_metrics(num_glyphs)
          nhm = @tables["hhea"][34, 2].unpack1("n")
          hmtx = @tables["hmtx"]
          @advances = []
          @lsbs = []
          num_glyphs.times do |gid|
            if gid < nhm
              @advances << hmtx[gid * 4, 2].unpack1("n")
              @lsbs << hmtx[(gid * 4) + 2, 2].unpack1("s>")
            else
              @advances << @advances.last
              @lsbs << hmtx[(nhm * 4) + ((gid - nhm) * 2), 2].unpack1("s>")
            end
          end
          long = @tables["head"][50, 2].unpack1("s>") == 1
          @loca = long ? @tables["loca"].unpack("N*") : @tables["loca"].unpack("n*").map { |v| v * 2 }
          @gvar = GvarReader.new(@tables["gvar"])
          @hvar = @tables["HVAR"] ? ItemVariationStore.new(@tables["HVAR"]) : nil
        end

        def raw_glyph(gid)
          @tables["glyf"].byteslice(@loca[gid]...@loca[gid + 1]) || "".b
        end

        def instance_glyph(gid)
          outline = GlyphOutline.parse(raw_glyph(gid))
          orig = outline.points
          n = orig.size
          xmin = outline.empty? ? 0 : raw_glyph(gid)[2, 2].unpack1("s>")
          pp1x = xmin - @lsbs[gid]
          total = Array.new(n + 4) { [0.0, 0.0] }
          @gvar.tuples_for(gid, n + 4).each do |t|
            s = tuple_scalar(t)
            next if s.zero?

            dx, dy = expand_deltas(t, outline, orig)
            (n + 4).times do |i|
              total[i][0] += s * dx[i]
              total[i][1] += s * dy[i]
            end
          end
          pts = orig.each_with_index.map do |(x, y), i|
            [round(x + total[i][0]), round(y + total[i][1])]
          end
          advance = if @hvar
                      @advances[gid] + round(@hvar.advance_delta(gid, @norm))
                    else
                      round(pp1x + @advances[gid] + total[n + 1][0]) -
                        round(pp1x + total[n][0])
                    end
          Glyph.new(outline, pts, [advance, 0].max, nil, nil)
        end

        def round(value)
          (value + 0.5).floor
        end

        def tuple_scalar(tuple)
          scalar = 1.0
          tuple.peak.each_with_index do |peak, i|
            next if peak.zero?

            v = @norm[i]
            next if v == peak

            lo, hi = if tuple.intermediate?
                       [tuple.start[i], tuple.end[i]]
                     else
                       [0.0, peak].minmax
                     end
            next if lo > peak || peak > hi || (lo.negative? && hi.positive?)
            return 0.0 if v <= lo || hi <= v

            scalar *= v < peak ? (v - lo) / (peak - lo) : (hi - v) / (hi - peak)
          end
          scalar
        end

        # Full per-point delta arrays (length n + 4), IUP applied when only
        # some points were given.
        def expand_deltas(tuple, outline, orig)
          total = orig.size + 4
          return [tuple.dx, tuple.dy] if tuple.points.nil?

          dx = Array.new(total)
          dy = Array.new(total)
          tuple.points.each_with_index do |p, i|
            next if p >= total

            dx[p] = tuple.dx[i]
            dy[p] = tuple.dy[i]
          end
          unless outline.composite?
            iup(orig.map(&:first), dx, outline.end_pts)
            iup(orig.map(&:last), dy, outline.end_pts)
          end
          [dx.map { |v| v || 0 }, dy.map { |v| v || 0 }]
        end

        def iup(coords, deltas, ends)
          start = 0
          ends.each do |last|
            touched = (start..last).select { |i| deltas[i] }
            if touched.empty?
              (start..last).each { |i| deltas[i] = 0 }
            elsif touched.size == 1
              (start..last).each { |i| deltas[i] = deltas[touched.first] }
            else
              touched.each_with_index do |t, k|
                nxt = touched[(k + 1) % touched.size]
                i = t
                loop do
                  i = i == last ? start : i + 1
                  break if i == nxt

                  deltas[i] = iup_value(coords[i], coords[t], deltas[t],
                                        coords[nxt], deltas[nxt])
                end
              end
            end
            start = last + 1
          end
        end

        def iup_value(coord, ref1, delta1, ref2, delta2)
          return (delta1 == delta2 ? delta1 : 0) if ref1 == ref2

          ref1, delta1, ref2, delta2 = ref2, delta2, ref1, delta1 if ref1 > ref2
          return delta1 if coord <= ref1
          return delta2 if coord >= ref2

          delta1 + ((coord - ref1) * (delta2 - delta1) / (ref2 - ref1).to_f)
        end

        # Bounding boxes; composites derive theirs from their components.
        def resolve_bounds(glyphs)
          glyphs.each_index { |gid| bbox_for(glyphs, gid, []) }
        end

        def bbox_for(glyphs, gid, stack)
          g = glyphs[gid]
          return g.bbox if g.bbox
          return g.bbox = [0, 0, 0, 0] if g.outline.empty? || stack.include?(gid)

          if g.outline.composite?
            corners = []
            g.outline.components.each_with_index do |c, i|
              sub = bbox_for(glyphs, c.gid, stack + [gid])
              next if glyphs[c.gid].outline.empty?

              corners.concat(transform_corners(sub, c, g.points[i]))
            end
            g.bbox = corners.empty? ? [0, 0, 0, 0] : g.outline.bounds_of(corners).map(&:round)
          else
            g.bbox = g.outline.bounds_of(g.points)
          end
        end

        def transform_corners(bbox, comp, offset)
          xmin, ymin, xmax, ymax = bbox
          t = comp.transform
          a, b, c, d = case t.bytesize
                       when 2 then s = t.unpack1("s>") / 16384.0
                                   [s, 0, 0, s]
                       when 4 then sx, sy = t.unpack("s>s>").map { |v| v / 16384.0 }
                                   [sx, 0, 0, sy]
                       when 8 then xs, s01, s10, ys = t.unpack("s>4").map { |v| v / 16384.0 }
                                   [xs, s01, s10, ys]
                       else [1, 0, 0, 1]
                       end
          [[xmin, ymin], [xmin, ymax], [xmax, ymin], [xmax, ymax]].map do |x, y|
            [(a * x) + (c * y) + offset[0], (b * x) + (d * y) + offset[1]]
          end
        end

        def write_glyf_loca(out, glyphs)
          glyf = +"".b
          loca = [0]
          glyphs.each do |g|
            data = g.outline.serialize(g.points, g.bbox)
            data << "\0".b until (data.bytesize % 4).zero?
            glyf << data
            loca << glyf.bytesize
          end
          out["glyf"] = glyf
          out["loca"] = loca.pack("N*")
          head = out["head"].dup
          head[50, 2] = [1].pack("s>")
          out["head"] = head
        end

        def write_hmtx(out, glyphs)
          hmtx = +"".b
          glyphs.each_with_index do |g, gid|
            lsb = g.outline.empty? ? @lsbs[gid] : g.bbox[0]
            g.data = [g.advance, lsb]
            hmtx << [g.advance, lsb].pack("ns>")
          end
          out["hmtx"] = hmtx
          hhea = out["hhea"].dup
          hhea[34, 2] = [glyphs.size].pack("n")
          out["hhea"] = hhea
        end

        def update_head_hhea(out, glyphs)
          drawn = glyphs.reject { |g| g.outline.empty? }
          return if drawn.empty?

          head = out["head"].dup
          head[36, 8] = [drawn.map { |g| g.bbox[0] }.min, drawn.map { |g| g.bbox[1] }.min,
                         drawn.map { |g| g.bbox[2] }.max, drawn.map { |g| g.bbox[3] }.max].pack("s>4")
          out["head"] = head
          hhea = out["hhea"].dup
          min_lsb = drawn.map { |g| g.data[1] }.min
          min_rsb = drawn.map { |g| g.data[0] - g.data[1] - (g.bbox[2] - g.bbox[0]) }.min
          max_ext = drawn.map { |g| g.data[1] + (g.bbox[2] - g.bbox[0]) }.max
          hhea[10, 8] = [glyphs.map(&:advance).max, min_lsb, min_rsb, max_ext].pack("ns>s>s>")
          out["hhea"] = hhea
        end

        def update_os2(out)
          return unless out["OS/2"]

          os2 = out["OS/2"].dup
          if @location.key?("wght")
            os2[4, 2] = [@location["wght"].round.clamp(1, 1000)].pack("n")
          end
          if @location.key?("wdth")
            nearest = WIDTH_CLASSES.each_index.min_by { |i| (WIDTH_CLASSES[i] - @location["wdth"]).abs }
            os2[6, 2] = [nearest + 1].pack("n")
          end
          out["OS/2"] = os2
        end

        def update_name(out)
          return unless out["name"]

          rewriter = NameRewriter.new(out["name"])
          out["name"] = rewriter.rename(instance_label(rewriter)).to_binary
        end

        def instance_label(rewriter)
          match = AxisSpace.named_instances(@tables["fvar"]).find do |inst|
            @space.tags.each_with_index.all? do |tag, i|
              (inst[:values][i] - @location[tag]).abs < 1e-6
            end
          end
          named = match && rewriter.lookup(match[:name_id])
          return named if named

          parts = @space.axes.reject { |a| @location[a.tag] == a.default }
            .map { |a| "#{a.tag.capitalize}#{format_value(@location[a.tag])}" }
          parts.empty? ? "Regular" : parts.join(" ")
        end

        def format_value(value)
          value == value.to_i ? value.to_i.to_s : value.to_s
        end
      end
    end
  end
end
