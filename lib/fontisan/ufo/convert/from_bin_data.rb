# frozen_string_literal: true

module Fontisan
  module Ufo
    module Convert
      # Converts a loaded TTF/OTF font (from Fontisan::FontLoader.load)
      # into a typed Fontisan::Ufo::Font. This is the reverse of
      # Compile::TtfCompiler / Compile::OtfCompiler.
      #
      # Reads each BinData table, extracts per-glyph data, and builds
      # Ufo::Glyph objects in the default layer.
      #
      # Composite (compound) glyphs are decomposed into contours — each
      # component's base glyph is resolved recursively, the 2×3 affine
      # transform is applied, and the transformed points are merged as
      # contours on the UFO glyph. This makes the glyph self-contained
      # (no dependency on component glyphs being present in the output).
      module FromBinData
        # @param font [Fontisan::SfntFont] loaded TTF or OTF
        # @return [Fontisan::Ufo::Font] typed UFO model
        def self.convert(font)
          ufo = Ufo::Font.new
          ufo.ufo_version = 3

          extract_info(font, ufo)
          extract_glyphs(font, ufo)
          ufo
        end

        # Map head/hhea/OS2/name/post fields → Ufo::Info.
        def self.extract_info(font, ufo)
          info = ufo.info

          head = font.table("head")
          if head
            info.units_per_em = head.units_per_em
            info.version_major = 1
            info.version_minor = 0
          end

          hhea = font.table("hhea")
          if hhea
            info.ascender = hhea.ascent
            info.descender = hhea.descent
            info.open_type_hhea_line_gap = hhea.line_gap
          end

          os2 = font.table("OS/2")
          if os2
            info.open_type_os2_weight_class = os2.us_weight_class
            info.open_type_os2_width_class = os2.us_width_class
          end

          extract_name_records(font, info)
          extract_post(font, info)
        rescue NoMethodError
          # Some tables may not be present in all fonts; skip silently
        end

        def self.extract_name_records(font, info)
          name_table = font.table("name")
          return unless name_table

          records = name_table.respond_to?(:name_records) ? name_table.name_records : []
          records.each do |record|
            next unless record.platform_id == 3 && record.encoding_id == 1 # Windows Unicode BMP

            value = decode_name_value(record, name_table)
            next unless value

            case record.name_id
            when 0 then info.copyright = value
            when 1 then info.family_name = value
            when 2 then info.style_name = value
            when 4 then info.postscript_full_name = value
            when 6 then info.postscript_font_name = value
            end
          end
        end

        def self.decode_name_value(record, name_table)
          raw = if name_table.respond_to?(:string_for_record)
                  name_table.string_for_record(record)
                end

          if raw && raw.encoding == Encoding::UTF_16BE
            raw.encode("UTF-8")
          elsif raw && raw.bytesize >= 2 && raw.getbyte(0).between?(0,
                                                                    127) && raw.getbyte(1).zero?
            # Looks like UTF-16BE
            raw.force_encoding("UTF-16BE").encode("UTF-8")
          else
            raw&.force_encoding("UTF-8")
          end
        rescue Encoding::InvalidByteSequenceError, Encoding::ConverterNotFoundError
          raw&.force_encoding("UTF-8")
        end

        def self.extract_post(font, info)
          post = font.table("post")
          return unless post

          if post.respond_to?(:italic_angle)
            info.italic_angle = post.italic_angle
          elsif post.respond_to?(:italic_angle_raw)
            raw = post.italic_angle_raw
            info.italic_angle = raw.to_i / 65536.0
          end
        rescue NoMethodError
          # post table may not have italic_angle
        end

        # Extract every glyph from glyf (TTF) or CFF (OTF).
        def self.extract_glyphs(font, ufo)
          cmap = build_cmap_lookup(font)
          widths = build_width_lookup(font)
          num_glyphs = font.table("maxp")&.num_glyphs || 0

          if font.has_table?("glyf")
            extract_truetype_glyphs(font, ufo, cmap, widths, num_glyphs)
          elsif font.has_table?("CFF ")
            extract_cff_glyphs(font, ufo, cmap, widths, num_glyphs)
          end
        end

        # Build {codepoint → gid} from the cmap table.
        def self.build_cmap_lookup(font)
          cmap_table = font.table("cmap")
          return {} unless cmap_table

          mappings = cmap_table.respond_to?(:unicode_mappings) ? cmap_table.unicode_mappings : {}
          # Invert: gid → [codepoints]
          inverted = Hash.new { |h, k| h[k] = [] }
          mappings.each { |cp, gid| inverted[gid] << cp }
          inverted
        end

        # Build {gid → advance_width} from hmtx.
        def self.build_width_lookup(font)
          hmtx = font.table("hmtx")
          return {} unless hmtx

          hhea = font.table("hhea")
          maxp = font.table("maxp")
          num_h_metrics = hhea&.number_of_h_metrics || 1
          num_glyphs = maxp&.num_glyphs || 0

          # Hmtx requires context-aware parsing before metric_for works.
          if hmtx.respond_to?(:parse_with_context)
            hmtx.parse_with_context(num_h_metrics, num_glyphs)
          end

          widths = {}
          num_glyphs.times do |gid|
            metric = hmtx.respond_to?(:metric_for) ? hmtx.metric_for(gid) : nil
            widths[gid] = metric ? metric[:advance_width] : 0
          end
          widths
        rescue RuntimeError
          # If hmtx parsing fails, return empty widths
          {}
        end

        # TTF: extract contours from glyf table via SimpleGlyph.
        def self.extract_truetype_glyphs(font, ufo, cmap, widths, num_glyphs)
          glyf = font.table("glyf")
          loca = font.table("loca")
          head = font.table("head")
          return unless glyf && loca && head

          # Tables need context-aware initialization before per-glyph access.
          if loca.respond_to?(:parse_with_context)
            loca.parse_with_context(head.index_to_loc_format,
                                    num_glyphs)
          end

          num_glyphs.times do |gid|
            glyph_name = glyph_name_for(font, gid) || "glyph#{gid}"
            ufo_glyph = Ufo::Glyph.new(name: glyph_name)
            ufo_glyph.width = widths.fetch(gid, 0).to_f

            cmap.fetch(gid, []).each { |cp| ufo_glyph.add_unicode(cp) }

            simple = begin
              glyf.glyph_for(gid, loca, head)
            rescue StandardError
              nil
            end

            if simple.is_a?(Fontisan::Tables::SimpleGlyph)
              extract_simple_contours(simple, ufo_glyph)
            elsif simple.respond_to?(:compound?) && simple.compound?
              extract_compound_contours(simple, ufo_glyph, glyf, loca, head)
            end

            # Always add the glyph, even if it has no contours. This
            # ensures gid → array index alignment (no gaps from skipped
            # glyphs). Without this, high-gid Plane 1 codepoints are
            # silently dropped because the array is shorter than maxp.
            ufo.layers.default_layer.add(ufo_glyph)
          end
        end

        # Convert a SimpleGlyph's contours + points into UFO contours.
        def self.extract_simple_contours(simple, ufo_glyph)
          num_contours = simple.end_pts_of_contours&.size || 0

          num_contours.times do |ci|
            points = simple.points_for_contour(ci)
            next unless points && !points.empty?

            ufo_points = points.map do |pt|
              x = pt[:x] || pt["x"]
              y = pt[:y] || pt["y"]
              on_curve = pt[:on_curve].nil? || pt[:on_curve]
              type = on_curve ? "line" : "offcurve"
              Ufo::Point.new(x: x.to_f, y: y.to_f, type: type)
            end
            ufo_glyph.add_contour(Ufo::Contour.new(ufo_points))
          end
        end

        # OTF: extract outlines from CFF charstrings.
        def self.extract_cff_glyphs(font, ufo, cmap, widths, num_glyphs)
          cff = font.table("CFF ")
          return extract_cff_glyphs_stub(font, ufo, cmap, widths, num_glyphs) unless cff

          num_glyphs.times do |gid|
            glyph_name = glyph_name_for(font, gid) || "gid#{gid}"
            ufo_glyph = Ufo::Glyph.new(name: glyph_name)
            ufo_glyph.width = widths.fetch(gid, 0).to_f
            cmap.fetch(gid, []).each { |cp| ufo_glyph.add_unicode(cp) }

            charstring = cff.charstring_for_glyph(gid)
            convert_cff_path_to_ufo(charstring.path, ufo_glyph) if charstring

            ufo.layers.default_layer.add(ufo_glyph)
          end
        end

        # Fallback: widths only, no contours (used when CFF table can't
        # be parsed — e.g., corrupted or unsupported variant).
        def self.extract_cff_glyphs_stub(font, ufo, cmap, widths, num_glyphs)
          num_glyphs.times do |gid|
            glyph_name = glyph_name_for(font, gid) || "gid#{gid}"
            ufo_glyph = Ufo::Glyph.new(name: glyph_name)
            ufo_glyph.width = widths.fetch(gid, 0).to_f
            cmap.fetch(gid, []).each { |cp| ufo_glyph.add_unicode(cp) }
            ufo.layers.default_layer.add(ufo_glyph)
          end
        end

        # Convert a CFF CharString path (array of command hashes) to
        # UFO contours. Each :move_to starts a new contour; :line_to
        # and :curve_to append points to the current contour. Cubic
        # bezier curves produce 2 offcurve + 1 curve points per
        # segment (GLIF convention).
        def self.convert_cff_path_to_ufo(path, glyph)
          return if path.empty?

          current_contour = nil

          path.each do |cmd|
            case cmd[:type]
            when :move_to
              glyph.add_contour(current_contour) if current_contour
              current_contour = Ufo::Contour.new
              current_contour.points << Ufo::Point.new(
                x: cmd[:x].to_i, y: cmd[:y].to_i, type: "move",
              )
            when :line_to
              next unless current_contour

              current_contour.points << Ufo::Point.new(
                x: cmd[:x].to_i, y: cmd[:y].to_i, type: "line",
              )
            when :curve_to
              next unless current_contour

              current_contour.points << Ufo::Point.new(
                x: cmd[:x1].to_i, y: cmd[:y1].to_i, type: "offcurve",
              )
              current_contour.points << Ufo::Point.new(
                x: cmd[:x2].to_i, y: cmd[:y2].to_i, type: "offcurve",
              )
              current_contour.points << Ufo::Point.new(
                x: cmd[:x].to_i, y: cmd[:y].to_i, type: "curve",
              )
            end
          end

          glyph.add_contour(current_contour) if current_contour
        end

        # Compound (composite) glyph: recursively flatten into UFO contours.
        # Mirrors Stitcher::Source#flatten_compound_into — resolves each
        # component's base glyph, applies the 2x3 affine transform, and
        # merges the result as contours on the UFO glyph.
        MAX_COMPOUND_DEPTH = 32

        def self.extract_compound_contours(compound, ufo_glyph, glyf, loca, head)
          flatten_compound(compound, ufo_glyph, glyf, loca, head, Set.new, 0)
        end

        def self.flatten_compound(compound, ufo_glyph, glyf, loca, head, visited, depth)
          return if depth > MAX_COMPOUND_DEPTH
          return if visited.include?(compound.glyph_id)

          visited = visited.dup.add(compound.glyph_id)

          compound.components.each do |component|
            next unless component.respond_to?(:args_are_xy?) ? component.args_are_xy? : true

            raw = begin
              glyf.glyph_for(component.glyph_index, loca, head)
            rescue StandardError
              nil
            end
            next unless raw

            matrix = component.transformation_matrix

            if raw.respond_to?(:simple?) && raw.simple?
              flatten_simple_component(raw, ufo_glyph, matrix)
            elsif raw.respond_to?(:compound?) && raw.compound?
              flatten_compound(raw, ufo_glyph, glyf, loca, head, visited, depth + 1)
            end
          end
        end

        def self.flatten_simple_component(simple, ufo_glyph, matrix)
          transform = Ufo::Transformation.new(
            a: matrix[0], b: matrix[1],
            c: matrix[2], d: matrix[3],
            e: matrix[4], f: matrix[5]
          )
          num_contours = simple.end_pts_of_contours&.size || 0
          return if num_contours.zero?

          num_contours.times do |ci|
            points = simple.points_for_contour(ci)
            next unless points && !points.empty?

            ufo_points = points.map do |pt|
              x = (pt[:x] || pt["x"]).to_f
              y = (pt[:y] || pt["y"]).to_f
              tx, ty = transform.apply(x, y)
              on_curve = pt[:on_curve].nil? || pt[:on_curve]
              type = on_curve ? "line" : "offcurve"
              Ufo::Point.new(x: tx, y: ty, type: type)
            end
            ufo_glyph.add_contour(Ufo::Contour.new(ufo_points))
          end
        end

        # Look up a glyph name from the post table (v2.0) or synthesize.
        def self.glyph_name_for(font, gid)
          post = font.table("post")
          return nil unless post

          if post.respond_to?(:glyph_name)
            name = post.glyph_name(gid)
            return name unless name.nil? || name.empty?
          end

          nil
        rescue NoMethodError
          nil
        end

        private_class_method :extract_info, :extract_name_records, :decode_name_value,
                             :extract_post, :extract_glyphs, :build_cmap_lookup,
                             :build_width_lookup, :extract_truetype_glyphs,
                             :extract_simple_contours, :extract_compound_contours,
                             :flatten_compound, :flatten_simple_component,
                             :extract_cff_glyphs, :glyph_name_for
      end
    end
  end
end
