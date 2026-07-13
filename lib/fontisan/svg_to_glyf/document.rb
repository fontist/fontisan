# frozen_string_literal: true

require "nokogiri"

module Fontisan
  module SvgToGlyf
    # Walks an SVG XML document to extract path data and accumulated
    # transforms. The Document is the single source of truth for which
    # transforms apply to which paths and what coordinate space the
    # SVG defines (via viewBox).
    class Document
      attr_reader :viewbox, :source

      # @param xml [String] raw SVG XML
      def self.from_xml(xml)
        new(Nokogiri::XML(xml))
      end

      # @param path [String] file path to an .svg file
      def self.from_file(path)
        from_xml(File.read(path))
      end

      # @param doc [Nokogiri::XML::Document]
      def initialize(doc)
        @doc = doc
        @source = doc
        @viewbox = extract_viewbox
      end

      # Yield each <path> element's d= string along with the accumulated
      # AffineTransform from all ancestor <g> transform= attributes.
      #
      # @yieldparam path_data [String] the d= attribute value
      # @yieldparam transform [Geometry::AffineTransform] accumulated group transform
      def each_path(&)
        return enum_for(:each_path) unless block_given?

        walk(@doc.root, Geometry::AffineTransform.identity, &)
      end

      private

      # Parse the SVG viewBox attribute. The SVG spec allows either
      # whitespace- or comma-separated values: "0 0 1000 1000" or
      # "0,0,1000,1000". The four components are min_x, min_y, width,
      # height — all are significant for normalization.
      #
      # Falls back to the root element's width/height attributes (origin
      # assumed to be 0,0). Returns nil if no geometry can be derived.
      #
      # @return [Ufo::Bounds, nil]
      def extract_viewbox
        root = @doc.root
        return unless root

        vb = root.attribute("viewBox")&.value
        if vb
          parts = vb.split(/[\s,]+/).map(&:to_f)
          return if parts.length != 4

          min_x, min_y, w, h = parts
          return if w.zero? || h.zero?

          return Ufo::Bounds.new(min_x: min_x, min_y: min_y,
                                 max_x: min_x + w, max_y: min_y + h)
        end

        w = root.attribute("width")&.value&.to_f
        h = root.attribute("height")&.value&.to_f
        return if w.nil? || h.nil? || w.zero? || h.zero?

        Ufo::Bounds.new(min_x: 0, min_y: 0, max_x: w, max_y: h)
      end

      # Recursively walk the XML tree. When a <g> has a transform=,
      # compose it into the running accumulated transform. When a <path>
      # is found, yield its d= with the current accumulated transform.
      def walk(node, accumulated, &)
        return unless node

        node.children.each do |child|
          next unless child.element?

          case child.name
          when "g"
            child_transform = parse_transform(child)
            walk(child, accumulated.compose(child_transform), &)
          when "path"
            data = child.attribute("d")&.value
            yield(data, accumulated) if data
          end
        end
      end

      def parse_transform(element)
        raw = element.attribute("transform")&.value
        Geometry::TransformParser.parse(raw)
      end
    end
  end
end
