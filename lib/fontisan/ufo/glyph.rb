# frozen_string_literal: true

require "nokogiri"

module Fontisan
  module Ufo
    # A glyph in a UFO source. Holds contours, components, anchors,
    # guidelines, images, unicode codepoints, advance width/height,
    # and a custom-data bag (`lib`).
    #
    # The `.glif` XML format has multiple revisions (1, 2, 3); the
    # parser accepts all of them.
    class Glyph
      attr_accessor :width, :height, :note, :lib
      attr_reader :name, :unicodes, :contours, :components, :anchors,
                  :guidelines, :images

      def initialize(name:)
        @name = name.to_s
        @unicodes = []
        @width = 0.0
        @height = 0.0
        @contours = []
        @components = []
        @anchors = []
        @guidelines = []
        @images = []
        @note = nil
        @lib = Lib.new
      end

      def add_unicode(codepoint)
        @unicodes << codepoint.to_i
      end

      def add_contour(contour)
        @contours << contour
        contour
      end

      def add_component(component)
        @components << component
        component
      end

      def add_anchor(anchor)
        @anchors << anchor
        anchor
      end

      def add_guideline(guideline)
        @guidelines << guideline
        guideline
      end

      def add_image(image)
        @images << image
        image
      end

      # Composite glyphs reference other glyphs via components.
      def composite?
        !@components.empty?
      end

      # Total number of points across all contours.
      def point_count
        @contours.sum(&:point_count)
      end

      # @return [BoundingBox, nil] axis-aligned bbox of contours.
      def bbox
        return nil if @contours.empty?

        points = @contours.flat_map(&:points)
        return nil if points.empty?

        BoundingBox.new(
          x_min: points.map(&:x).min,
          y_min: points.map(&:y).min,
          x_max: points.map(&:x).max,
          y_max: points.map(&:y).max,
        )
      end

      # @param xml [String] the .glif XML body
      # @return [Glyph] parsed glyph
      def self.from_glif(xml)
        doc = Nokogiri::XML(xml)
        root = doc.root
        new(name: root["name"]).tap { |g| g.read_from(root) }
      end

      # Render this glyph back to .glif XML.
      # @return [String] XML text
      def to_glif
        builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml.glyph(name: @name, format: "2") do
            emit_advance(xml)
            emit_unicodes(xml)
            emit_outline(xml)
            emit_lib(xml)
            emit_note(xml)
          end
        end
        builder.to_xml
      end

      # Populate this glyph from a <glyph> Nokogiri node.
      def read_from(root)
        read_advance(root)
        read_unicodes(root)
        read_outline(root)
        read_anchors(root)
        read_guidelines(root)
        read_image(root)
        read_lib(root)
        read_note(root)
      end

      # Convert this glyph to a fontisan Models::Outline for use by
      # the CFF charstring builder.
      #
      # UFO contours use cubic Bezier curves ("curve" type with two
      # off-curve controls). Single off-curves are interpreted as
      # quadratic and degree-elevated to cubic.
      #
      # @return [Fontisan::Models::Outline]
      def to_outline
        commands = []
        bbox_hash = { x_min: 0, y_min: 0, x_max: 0, y_max: 0 }

        @contours.each do |contour|
          next if contour.points.empty?

          points = contour.points
          commands << { type: :move_to, x: points.first.x, y: points.first.y }

          i = 1
          while i < points.size
            pt = points[i]
            if pt.on_curve?
              commands << { type: :line_to, x: pt.x, y: pt.y }
              i += 1
            elsif i + 2 < points.size &&
                !points[i + 1].on_curve? && points[i + 2].on_curve?
              commands << {
                type: :curve_to,
                cx1: points[i].x, cy1: points[i].y,
                cx2: points[i + 1].x, cy2: points[i + 1].y,
                x: points[i + 2].x, y: points[i + 2].y
              }
              i += 3
            elsif i + 1 < points.size && points[i + 1].on_curve?
              prev = points[i - 1]
              nxt = points[i + 1]
              cx1 = prev.x + (2.0 / 3.0) * (pt.x - prev.x)
              cy1 = prev.y + (2.0 / 3.0) * (pt.y - prev.y)
              cx2 = nxt.x + (2.0 / 3.0) * (pt.x - nxt.x)
              cy2 = nxt.y + (2.0 / 3.0) * (pt.y - nxt.y)
              commands << {
                type: :curve_to,
                cx1: cx1, cy1: cy1, cx2: cx2, cy2: cy2,
                x: nxt.x, y: nxt.y
              }
              i += 2
            else
              i += 1
            end
          end

          commands << { type: :close_path }
        end

        bb = bbox
        if bb
          bbox_hash = {
            x_min: bb.x_min.to_i, y_min: bb.y_min.to_i,
            x_max: bb.x_max.to_i, y_max: bb.y_max.to_i
          }
        end

        Fontisan::Models::Outline.new(
          glyph_id: 0,
          commands: commands,
          bbox: bbox_hash,
          width: @width.to_i,
        )
      end

      private

      def read_advance(root)
        adv = root.at_xpath("advance")
        return unless adv

        @width = adv["width"].to_f if adv["width"]
        @height = adv["height"].to_f if adv["height"]
      end

      def read_unicodes(root)
        root.xpath("unicode").each do |u|
          hex = u["hex"] || u.text
          add_unicode(hex.to_i(16)) if hex
        end
      end

      def read_outline(root)
        outline = root.at_xpath("outline")
        return unless outline

        outline.xpath("contour").each do |c|
          add_contour(read_contour(c))
        end
        outline.xpath("component").each do |c|
          add_component(read_component(c))
        end
      end

      def read_contour(node)
        points = node.xpath("point").map do |p|
          Point.new(
            x: p["x"].to_f,
            y: p["y"].to_f,
            type: p["type"] || "offcurve",
            smooth: p["smooth"] == "yes",
          )
        end
        Contour.new(points)
      end

      def read_component(node)
        Component.new(
          base_glyph: node["base"],
          transformation: read_transformation(node),
          identifier: node["identifier"],
        )
      end

      def read_transformation(node)
        return nil unless node["xScale"] || node["yScale"] ||
          node["xyScale"] || node["yxScale"] ||
          node["xOffset"] || node["yOffset"]

        Transformation.new(
          a: node["xScale"]&.to_f || 1.0,
          b: node["xyScale"].to_f,
          c: node["yxScale"].to_f,
          d: node["yScale"]&.to_f || 1.0,
          e: node["xOffset"].to_f,
          f: node["yOffset"].to_f,
        )
      end

      def read_anchors(root)
        root.xpath("anchor").each do |a|
          add_anchor(Anchor.new(
                       x: a["x"].to_f,
                       y: a["y"].to_f,
                       name: a["name"],
                       identifier: a["identifier"],
                     ))
        end
      end

      def read_guidelines(root)
        root.xpath("guideline").each do |g|
          add_guideline(Guideline.new(
                          x: g["x"].to_f,
                          y: g["y"].to_f,
                          angle: g["angle"]&.to_f,
                          name: g["name"],
                          identifier: g["identifier"],
                        ))
        end
      end

      def read_image(root)
        img = root.at_xpath("image")
        return unless img && img["fileName"]

        add_image(Image.new(
                    file_name: img["fileName"],
                    transformation: read_transformation(img),
                    color: img["color"],
                  ))
      end

      def read_lib(root)
        lib_node = root.at_xpath("lib")
        return unless lib_node

        dict = lib_node.at_xpath("dict")
        return unless dict

        @lib = Lib.new(read_dict_to_hash(dict))
      end

      def read_note(root)
        note_node = root.at_xpath("note")
        @note = note_node.text if note_node
      end

      # Helper: read a <dict> Nokogiri node into a Hash. Reuses the
      # same key/value pair logic as Plist.parse but operates on the
      # inlined lib plist.
      def read_dict_to_hash(dict_node)
        result = {}
        children = dict_node.element_children.to_a
        while children.any?
          key_node = children.shift
          next unless key_node.name == "key"

          value_node = children.shift
          result[key_node.text] = read_plist_value(value_node)
        end
        result
      end

      def read_plist_value(node)
        case node.name
        when "string" then node.text
        when "integer" then node.text.to_i
        when "real" then node.text.to_f
        when "true" then true
        when "false" then false
        when "array" then node.element_children.map { |c| read_plist_value(c) }
        when "dict" then read_dict_to_hash(node)
        end
      end

      # ---------- emission ----------

      def emit_advance(xml)
        attrs = {}
        attrs[:width] = @width unless @width.zero?
        attrs[:height] = @height unless @height.zero?
        xml.advance(**attrs) unless attrs.empty?
      end

      def emit_unicodes(xml)
        @unicodes.each { |cp| xml.unicode(hex: format("%04X", cp)) }
      end

      def emit_outline(xml)
        return if @contours.empty? && @components.empty?

        xml.outline do
          @contours.each { |c| emit_contour(xml, c) }
          @components.each { |comp| emit_component(xml, comp) }
        end
      end

      def emit_contour(xml, contour)
        xml.contour do
          contour.points.each { |p| emit_point(xml, p) }
        end
      end

      def emit_point(xml, point)
        attrs = { x: point.x, y: point.y }
        attrs[:type] = point.type unless point.type == "offcurve"
        attrs[:smooth] = "yes" if point.smooth
        xml.point(**attrs)
      end

      def emit_component(xml, comp)
        attrs = { base: comp.base_glyph }
        if comp.transformation && !comp.transformation.identity?
          t = comp.transformation
          attrs[:xScale] = t.a
          attrs[:xyScale] = t.b
          attrs[:yxScale] = t.c
          attrs[:yScale] = t.d
          attrs[:xOffset] = t.e
          attrs[:yOffset] = t.f
        end
        attrs[:identifier] = comp.identifier if comp.identifier
        xml.component(**attrs)
      end

      def emit_lib(xml)
        return if @lib.data.empty?

        xml.lib do
          emit_dict(xml, @lib.data)
        end
      end

      def emit_dict(xml, hash)
        xml.dict do
          hash.each do |k, v|
            xml.key(k.to_s)
            emit_value(xml, v)
          end
        end
      end

      def emit_value(xml, v)
        case v
        when String then xml.string(v)
        when Integer then xml.integer(v)
        when Float then xml.real(v)
        when true then xml.__send__(true)
        when false then xml.__send__(false)
        when Array then xml.array { v.each { |i| emit_value(xml, i) } }
        when Hash then emit_dict(xml, v)
        else xml.string(v.to_s)
        end
      end

      def emit_note(xml)
        xml.note(@note) if @note
      end
    end

    # Plain-data bounding box (used by glyph bbox computation; not a
    # full OpenType table).
    BoundingBox = Struct.new(:x_min, :y_min, :x_max, :y_max, keyword_init: true)
  end
end
