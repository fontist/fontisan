# frozen_string_literal: true

require "nokogiri"

module Fontisan
  module SvgToGlyf
    # Walks an SVG XML document to extract path data and accumulated
    # transforms. The Document is the single source of truth for which
    # transforms apply to which paths and what coordinate space the
    # SVG defines (via viewBox).
    class Document
      attr_reader :viewbox_width, :viewbox_height, :source

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
        extract_viewbox
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

      def extract_viewbox
        root = @doc.root
        vb = root&.attribute("viewBox")&.value
        if vb
          _, _, w, h = vb.split(/\s+/).map(&:to_f)
          @viewbox_width = w
          @viewbox_height = h
        else
          @viewbox_width = (root&.attribute("width")&.value || DEFAULT_UPM).to_f
          @viewbox_height = (root&.attribute("height")&.value || DEFAULT_UPM).to_f
        end
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
