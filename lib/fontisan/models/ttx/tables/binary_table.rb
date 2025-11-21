# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ttx
      module Tables
        # BinaryTable represents unparsed tables in TTX format
        #
        # Used as a fallback for tables that don't have specific
        # parsers, storing them as hexdata following fonttools format.
        class BinaryTable < Lutaml::Model::Serializable
          attribute :tag, :string
          attribute :hexdata, :string

          # Custom serialization since we need dynamic root element
          # based on table tag
          def to_xml(options = {})
            builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
              xml.send(tag.to_sym) do
                xml.hexdata do
                  xml.text("\n    #{format_hexdata(hexdata)}\n  ")
                end
              end
            end

            if options[:pretty]
              builder.doc.root.to_xml(indent: options.fetch(:indent, 2))
            else
              builder.to_xml
            end
          end

          # Parse from XML
          def self.from_xml(xml_string, tag)
            doc = Nokogiri::XML(xml_string)
            table_elem = doc.at_xpath("//#{tag}")
            return nil unless table_elem

            hexdata_elem = table_elem.at_xpath("hexdata")
            hexdata = hexdata_elem ? parse_hexdata(hexdata_elem.text) : ""

            new(tag: tag, hexdata: hexdata)
          end

          private

          # Format hexdata for output
          def format_hexdata(data)
            return "" if data.nil? || data.empty?

            hex = data.unpack1("H*")
            # Format in lines of 64 hex chars (32 bytes)
            hex.scan(/.{1,64}/).join("\n    ")
          end

          # Parse hexdata from XML
          def self.parse_hexdata(hex_str)
            hex_clean = hex_str.gsub(/\s+/, "")
            [hex_clean].pack("H*")
          end
        end
      end
    end
  end
end
