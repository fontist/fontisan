# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Immutable metadata about a stitcher output format. Single source
    # of truth for "given a format symbol, what compiler / collection
    # format / file extension does it use?". Adding a new format =
    # adding a +when+ branch in {resolve}; no other site in Stitcher
    # needs to know the mapping.
    class FormatMetadata
      attr_reader :name, :compiler_class, :collection_format, :extension

      # @param name [Symbol] canonical format name (:ttf, :otf, :otf2)
      # @param compiler_class [Class] the +Ufo::Compile::*Compiler+ that
      #   compiles a +Ufo::Font+ target into the format's binary
      # @param collection_format [Symbol] :ttc or :otc — the
      #   +Collection::Builder+ format used when packing multiple
      #   subfonts of this format into a collection
      # @param extension [String] file extension including the dot
      def initialize(name:, compiler_class:, collection_format:, extension:)
        @name = name
        @compiler_class = compiler_class
        @collection_format = collection_format
        @extension = extension
      end

      # Resolve a format name (Symbol or String) to its metadata.
      # Constants are referenced inside +when+ branches so autoload
      # fires only for the requested format, not all of them.
      #
      # @param name [Symbol, String]
      # @raise [ArgumentError] if +name+ is not a known stitcher format
      # @return [FormatMetadata]
      def self.resolve(name)
        case name.to_sym
        when :ttf
          new(name: :ttf, compiler_class: Ufo::Compile::TtfCompiler,
              collection_format: :ttc, extension: ".ttf")
        when :otf
          new(name: :otf, compiler_class: Ufo::Compile::OtfCompiler,
              collection_format: :otc, extension: ".otf")
        when :otf2
          new(name: :otf2, compiler_class: Ufo::Compile::Otf2Compiler,
              collection_format: :otc, extension: ".otf")
        else
          raise ArgumentError, "unknown format: #{name.inspect}"
        end
      end
    end
  end
end
