# frozen_string_literal: true

require "moxml"

module Fontisan
  module Ufo
    # Minimal XML plist parser/serializer for the files that UFO v3
    # uses. UFO uses XML plists exclusively; binary plists are not
    # used in the spec.
    #
    # The parser is typed at the value level: strings stay as String,
    # integers stay as Integer, booleans become true/false, dicts
    # become Hash<String, Object>, arrays become Array<Object>.
    # Dates, data blobs, and nested structures are supported.
    module Plist
      class ParseError < StandardError; end

      PLIST_DTD = "-//Apple//DTD PLIST 1.0//EN"
      PLIST_NS  = "http://www.apple.com/DTDs/PropertyList-1.0.dtd"

      # @param source [String, Moxml::Document] the XML plist
      # @return [Object] the deserialized value
      def self.parse(source)
        doc = parse_document(source)
        root = doc.root
        raise ParseError, "no <plist> root element" unless root&.name == "plist"

        parse_value(root.children.find do |c|
          c.element? || c.cdata? || c.text? && !c.text.strip.empty?
        end)
      end

      # @param value [Object] the value to serialize
      # @return [String] the XML plist text
      def self.emit(value)
        builder = Moxml::Builder.new(Moxml.new)
        builder.build do
          doctype("plist", PLIST_DTD, PLIST_NS)
          plist(version: "1.0") do
            Plist.emit_value(builder, value)
          end
        end
        # indent: 0 keeps the body on the single line Nokogiri's
        # AS_XML produced; expand_empty: false keeps its `<string/>`
        # self-closing shape for empty elements.
        builder.doc.to_xml(indent: 0, expand_empty: false)
      end

      # @return [Moxml::Document] the typed root
      def self.parse_document(source)
        source.is_a?(Moxml::Document) ? source : Moxml.parse(source)
      end

      # ---------- private-ish (called via module_function) ----------

      def self.parse_value(node)
        return nil if node.nil?

        case node.name
        when "string" then node.text
        when "integer" then node.text.to_i
        when "real" then node.text.to_f
        when "true" then true
        when "false" then false
        when "dict" then parse_dict(node)
        when "array" then parse_array(node)
        else
          raise ParseError, "unsupported plist element: <#{node.name}>"
        end
      end

      def self.parse_dict(node)
        result = {}
        children = node.element_children.to_a
        # dict children are key/value pairs (key first, then value)
        while children.any?
          key_node = children.shift
          unless key_node.name == "key"
            raise ParseError,
                  "dict key is not <key>"
          end

          value_node = children.shift
          result[key_node.text] = parse_value(value_node)
        end
        result
      end

      def self.parse_array(node)
        node.element_children.map { |child| parse_value(child) }
      end

      def self.emit_value(xml, value)
        case value
        when nil
          # No <nil/> in Apple's plist DTD; use a sentinel string.
          xml.string_
        when true then xml.true_
        when false then xml.false_
        when Integer then xml.integer(value.to_s)
        when Float then xml.real(value.to_s)
        # An empty string serializes as a self-closed <string/>, like
        # Nokogiri did; moxml keeps a paired form for a text child.
        when String then value.empty? ? xml.string_ : xml.string(value)
        when Symbol then xml.string(value.to_s)
        when Array then xml.array { value.each { |v| emit_value(xml, v) } }
        when Hash  then xml.dict { emit_dict_body(xml, value) }
        else
          raise ArgumentError, "cannot plist-encode #{value.class}"
        end
      end

      def self.emit_dict_body(xml, hash)
        hash.each do |k, v|
          xml.key(k.to_s)
          emit_value(xml, v)
        end
      end
    end
  end
end
