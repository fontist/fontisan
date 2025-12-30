# frozen_string_literal: true

require_relative "base_collection"

module Fontisan
  # OpenType Collection domain object
  #
  # Represents a complete OpenType Collection file (OTC). Inherits all shared
  # functionality from BaseCollection and implements OTC-specific behavior.
  #
  # @example Reading and extracting fonts
  #   File.open("fonts.otc", "rb") do |io|
  #     otc = OpenTypeCollection.read(io)
  #     puts otc.num_fonts  # => 4
  #     fonts = otc.extract_fonts(io)  # => [OpenTypeFont, OpenTypeFont, ...]
  #   end
  class OpenTypeCollection < BaseCollection
    # Get the font class for OpenType collections
    #
    # @return [Class] OpenTypeFont class
    def self.font_class
      require_relative "open_type_font"
      OpenTypeFont
    end

    # Get the collection format identifier
    #
    # @return [String] "OTC" for OpenType Collection
    def self.collection_format
      "OTC"
    end

    # Extract fonts as OpenTypeFont objects
    #
    # Reads each font from the OTC file and returns them as OpenTypeFont objects.
    # This method uses the from_collection method.
    #
    # @param io [IO] Open file handle to read fonts from
    # @return [Array<OpenTypeFont>] Array of font objects
    def extract_fonts(io)
      require_relative "open_type_font"

      font_offsets.map do |offset|
        OpenTypeFont.from_collection(io, offset)
      end
    end
  end
end
