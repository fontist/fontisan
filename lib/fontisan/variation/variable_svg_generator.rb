# frozen_string_literal: true

require_relative "instance_generator"
require_relative "../converters/svg_generator"

module Fontisan
  module Variation
    # Generates SVG fonts from variable fonts at specific coordinates
    #
    # [`VariableSvgGenerator`](lib/fontisan/variation/variable_svg_generator.rb)
    # combines instance generation with SVG conversion to create static SVG
    # fonts from variable fonts at any point in the design space.
    #
    # Process:
    # 1. Accept variable font + axis coordinates
    # 2. Generate static instance using InstanceGenerator
    # 3. Build temporary font from instance tables
    # 4. Delegate to SvgGenerator for SVG creation
    # 5. Return SVG with variation metadata
    #
    # This enables generating SVG fonts at specific weights, widths, or other
    # variation axes without creating intermediate font files.
    #
    # @example Generate SVG at Bold weight
    #   generator = VariableSvgGenerator.new(variable_font, { "wght" => 700.0 })
    #   svg_result = generator.generate
    #   File.write("bold.svg", svg_result[:svg_xml])
    #
    # @example Generate SVG at specific width and weight
    #   coords = { "wght" => 700.0, "wdth" => 75.0 }
    #   generator = VariableSvgGenerator.new(variable_font, coords)
    #   svg_result = generator.generate(pretty_print: true)
    class VariableSvgGenerator
      # @return [TrueTypeFont, OpenTypeFont] Variable font
      attr_reader :font

      # @return [Hash<String, Float>] Design space coordinates
      attr_reader :coordinates

      # Initialize generator
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font
      # @param coordinates [Hash<String, Float>] Design space coordinates
      # @raise [Error] If font is not a variable font
      def initialize(font, coordinates = {})
        @font = font
        @coordinates = coordinates || {}

        validate_variable_font!
      end

      # Generate SVG font at specified coordinates
      #
      # Creates a static instance at the given coordinates and converts
      # it to SVG format. Returns the same format as SvgGenerator for
      # consistency.
      #
      # @param options [Hash] SVG generation options
      # @option options [Boolean] :pretty_print Pretty print XML (default: true)
      # @option options [Array<Integer>] :glyph_ids Specific glyphs (default: all)
      # @option options [Integer] :max_glyphs Maximum glyphs (default: all)
      # @option options [String] :font_id Font ID for SVG
      # @option options [Integer] :default_advance Default advance width
      # @return [Hash] Hash with :svg_xml key containing SVG XML string
      # @raise [Error] If generation fails
      def generate(options = {})
        # Generate static instance tables
        instance_tables = generate_static_instance

        # Build temporary font from instance tables
        static_font = build_font_from_tables(instance_tables)

        # Generate SVG using standard generator
        svg_generator = Converters::SvgGenerator.new
        result = svg_generator.convert(static_font, options)

        # Add variation metadata to result
        result[:variation_metadata] = {
          coordinates: @coordinates,
          source_font: extract_font_name,
        }

        result
      end

      # Generate SVG for a named instance
      #
      # @param instance_index [Integer] Index of named instance in fvar
      # @param options [Hash] SVG generation options
      # @return [Hash] Hash with :svg_xml key
      def generate_named_instance(instance_index, options = {})
        instance_generator = InstanceGenerator.new(@font)
        instance_tables = instance_generator.generate_named_instance(instance_index)

        static_font = build_font_from_tables(instance_tables)
        svg_generator = Converters::SvgGenerator.new
        result = svg_generator.convert(static_font, options)

        # Add instance metadata
        result[:variation_metadata] = {
          instance_index: instance_index,
          source_font: extract_font_name,
        }

        result
      end

      # Get default coordinates for font
      #
      # Returns all axes at their default values.
      #
      # @return [Hash<String, Float>] Default coordinates
      def default_coordinates
        return {} unless @font.has_table?("fvar")

        fvar = @font.table("fvar")
        return {} unless fvar

        coords = {}
        fvar.axes.each do |axis|
          coords[axis.axis_tag] = axis.default_value
        end
        coords
      end

      # Get list of named instances
      #
      # @return [Array<Hash>] Array of instance info
      def named_instances
        return [] unless @font.has_table?("fvar")

        fvar = @font.table("fvar")
        return [] unless fvar

        fvar.instances.map.with_index do |instance, index|
          {
            index: index,
            name: instance[:subfamily_name_id],
            coordinates: build_instance_coordinates(instance, fvar.axes),
          }
        end
      end

      private

      # Validate that font is a variable font
      #
      # @raise [Error] If not a variable font
      def validate_variable_font!
        unless @font.has_table?("fvar")
          raise Fontisan::Error,
                "Font must be a variable font (missing fvar table)"
        end

        # Check for variation data
        has_gvar = @font.has_table?("gvar")
        has_cff2 = @font.has_table?("CFF2")

        unless has_gvar || has_cff2
          raise Fontisan::Error,
                "Variable font must have gvar (TrueType) or CFF2 (PostScript) table"
        end
      end

      # Generate static instance at current coordinates
      #
      # @return [Hash<String, String>] Instance tables
      def generate_static_instance
        # Use coordinates or defaults if none specified
        coords = @coordinates.empty? ? default_coordinates : @coordinates

        instance_generator = InstanceGenerator.new(@font, coords)
        instance_generator.generate
      end

      # Build a font object from instance tables
      #
      # Creates a minimal font object that can be used by SvgGenerator.
      # This is a lightweight wrapper around the table data.
      #
      # @param tables [Hash<String, String>] Font tables
      # @return [Object] Font-like object
      def build_font_from_tables(tables)
        # Create a simple font wrapper that implements the minimal
        # interface needed by SvgGenerator
        InstanceFontWrapper.new(@font, tables)
      end

      # Extract font name for metadata
      #
      # @return [String] Font name
      def extract_font_name
        name_table = @font.table("name")
        return "Unknown" unless name_table

        # Try font family name
        family = name_table.font_family.first
        return family if family && !family.empty?

        "Unknown"
      rescue StandardError
        "Unknown"
      end

      # Build coordinates from instance
      #
      # @param instance [Hash] Instance data
      # @param axes [Array] Variation axes
      # @return [Hash<String, Float>] Coordinates
      def build_instance_coordinates(instance, axes)
        coords = {}
        instance[:coordinates].each_with_index do |value, index|
          next if index >= axes.length

          axis = axes[index]
          coords[axis.axis_tag] = value
        end
        coords
      end

      # Wrapper class for instance font tables
      #
      # Provides minimal interface needed by SvgGenerator while using
      # instance tables instead of original font tables.
      class InstanceFontWrapper
        # @return [Hash<String, String>] Font tables
        attr_reader :table_data

        # Initialize wrapper
        #
        # @param original_font [Object] Original variable font
        # @param instance_tables [Hash<String, String>] Instance tables
        def initialize(original_font, instance_tables)
          @original_font = original_font
          @table_data = instance_tables
        end

        # Get table by tag
        #
        # @param tag [String] Table tag
        # @return [Object, nil] Table or nil
        def table(tag)
          # Use instance table if available, otherwise fall back to original
          if @table_data.key?(tag)
          end
          @original_font.table(tag)
        end

        # Check if table exists
        #
        # @param tag [String] Table tag
        # @return [Boolean] True if table exists
        def has_table?(tag)
          @table_data.key?(tag) || @original_font.has_table?(tag)
        end

        # Forward other methods to original font
        def method_missing(method, ...)
          @original_font.send(method, ...)
        end

        def respond_to_missing?(method, include_private = false)
          @original_font.respond_to?(method, include_private) || super
        end
      end
    end
  end
end
