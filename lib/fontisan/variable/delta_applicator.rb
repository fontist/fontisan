# frozen_string_literal: true

require "yaml"
require_relative "axis_normalizer"
require_relative "region_matcher"
require_relative "glyph_delta_processor"
require_relative "metric_delta_processor"

module Fontisan
  module Variable
    # Main orchestrator for delta application in variable fonts
    #
    # Coordinates the entire delta application pipeline:
    # 1. Normalizes user coordinates to design space
    # 2. Calculates region scalars based on normalized coordinates
    # 3. Applies glyph outline deltas via GlyphDeltaProcessor
    # 4. Applies metric deltas via MetricDeltaProcessor
    #
    # This is the primary interface for applying variation deltas to fonts.
    #
    # @example Apply deltas at specific coordinates
    #   applicator = DeltaApplicator.new(font)
    #   result = applicator.apply({ "wght" => 700, "wdth" => 100 })
    #   # => { normalized_coords: {...}, region_scalars: [...],
    #   #      glyph_deltas: {...}, metric_deltas: {...} }
    class DeltaApplicator
      # @return [Hash] Configuration settings
      attr_reader :config

      # @return [AxisNormalizer] Axis normalizer
      attr_reader :axis_normalizer

      # @return [RegionMatcher] Region matcher
      attr_reader :region_matcher

      # @return [GlyphDeltaProcessor] Glyph delta processor
      attr_reader :glyph_delta_processor

      # @return [MetricDeltaProcessor] Metric delta processor
      attr_reader :metric_delta_processor

      # Initialize the delta applicator
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font object
      # @param config [Hash] Optional configuration overrides
      def initialize(font, config = {})
        @font = font
        @config = load_config.merge(config)

        # Load variation tables
        @fvar = load_table("fvar")
        @gvar = load_table("gvar")
        @hvar = load_table("HVAR")
        @vvar = load_table("VVAR")
        @mvar = load_table("MVAR")

        # Initialize components
        initialize_components
      end

      # Apply deltas at specified user coordinates
      #
      # @param user_coords [Hash<String, Numeric>] User coordinates
      # @return [Hash] Delta application results
      def apply(user_coords)
        # Validate we have required tables
        unless @fvar
          raise ArgumentError,
                "Font does not have fvar table (not a variable font)"
        end

        # Step 1: Normalize coordinates
        normalized_coords = @axis_normalizer.normalize(user_coords)

        # Step 2: Calculate region scalars
        region_scalars = @region_matcher.match(normalized_coords)

        # Step 3: Prepare result structure
        result = {
          user_coords: user_coords,
          normalized_coords: normalized_coords,
          region_scalars: region_scalars,
          glyph_deltas: {},
          metric_deltas: {},
          font_metrics: {},
        }

        # Step 4: Apply font-level metrics if MVAR present
        if @metric_delta_processor.has_mvar?
          result[:font_metrics] =
            @metric_delta_processor.apply_font_metrics(region_scalars)
        end

        result
      end

      # Apply deltas to a specific glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param user_coords [Hash<String, Numeric>] User coordinates
      # @return [Hash] Glyph delta result
      def apply_glyph(glyph_id, user_coords)
        # Normalize and get region scalars
        normalized_coords = @axis_normalizer.normalize(user_coords)
        region_scalars = @region_matcher.match(normalized_coords)

        result = {
          glyph_id: glyph_id,
          normalized_coords: normalized_coords,
        }

        # Apply glyph outline deltas if gvar present
        if @glyph_delta_processor
          result[:outline_deltas] = @glyph_delta_processor.apply_deltas(
            glyph_id,
            region_scalars,
          )
        end

        # Apply metric deltas
        result[:metric_deltas] = @metric_delta_processor.apply_deltas(
          glyph_id,
          region_scalars,
        )

        result
      end

      # Apply deltas to multiple glyphs
      #
      # @param glyph_ids [Array<Integer>] Glyph IDs
      # @param user_coords [Hash<String, Numeric>] User coordinates
      # @return [Hash<Integer, Hash>] Results by glyph ID
      def apply_glyphs(glyph_ids, user_coords)
        # Normalize once for all glyphs
        normalized_coords = @axis_normalizer.normalize(user_coords)
        region_scalars = @region_matcher.match(normalized_coords)

        glyph_ids.each_with_object({}) do |glyph_id, results|
          results[glyph_id] = {
            outline_deltas: @glyph_delta_processor&.apply_deltas(glyph_id,
                                                                 region_scalars),
            metric_deltas: @metric_delta_processor.apply_deltas(glyph_id,
                                                                region_scalars),
          }
        end
      end

      # Get advance width delta for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param user_coords [Hash<String, Numeric>] User coordinates
      # @return [Integer] Advance width delta
      def advance_width_delta(glyph_id, user_coords)
        normalized_coords = @axis_normalizer.normalize(user_coords)
        region_scalars = @region_matcher.match(normalized_coords)

        @metric_delta_processor.advance_width_delta(glyph_id, region_scalars)
      end

      # Check if font is a variable font
      #
      # @return [Boolean] True if variable font
      def variable_font?
        !@fvar.nil?
      end

      # Get axis information
      #
      # @return [Hash] Axis information from fvar
      def axes
        return {} unless @fvar

        @fvar.axes.each_with_object({}) do |axis, hash|
          # Convert BinData::String to regular Ruby String
          tag = axis.axis_tag.to_s
          hash[tag] = {
            min: axis.min_value,
            default: axis.default_value,
            max: axis.max_value,
            name_id: axis.axis_name_id,
          }
        end
      end

      # Get available axis tags
      #
      # @return [Array<String>] Axis tags
      def axis_tags
        @axis_normalizer.axis_tags
      end

      # Get number of variation regions
      #
      # @return [Integer] Region count
      def region_count
        @region_matcher.region_count
      end

      private

      # Load configuration from YAML file
      #
      # @return [Hash] Configuration hash
      def load_config
        config_path = File.join(__dir__, "..", "config",
                                "variable_settings.yml")
        loaded = YAML.load_file(config_path)
        # Convert string keys to symbol keys for consistency
        deep_symbolize_keys(loaded)
      rescue StandardError
        # Return default config
        {
          validation: {
            validate_tables: true,
            check_required_tables: true,
          },
        }
      end

      # Recursively convert hash keys to symbols
      #
      # @param hash [Hash] Hash with string keys
      # @return [Hash] Hash with symbol keys
      def deep_symbolize_keys(hash)
        hash.each_with_object({}) do |(key, value), result|
          new_key = key.to_sym
          new_value = value.is_a?(Hash) ? deep_symbolize_keys(value) : value
          result[new_key] = new_value
        end
      end

      # Initialize all components
      def initialize_components
        # Initialize axis normalizer
        @axis_normalizer = AxisNormalizer.new(@fvar, @config)

        # Get axis tags for region matcher - convert BinData::String to String
        axis_tags = @fvar ? @fvar.axes.map { |axis| axis.axis_tag.to_s } : []

        # Initialize region matcher
        # Get variation region list from one of the tables
        variation_region_list = get_variation_region_list
        @region_matcher = RegionMatcher.new(variation_region_list, axis_tags,
                                            @config)

        # Initialize glyph delta processor
        @glyph_delta_processor = if @gvar
                                   GlyphDeltaProcessor.new(@gvar,
                                                           @config)
                                 end

        # Initialize metric delta processor
        @metric_delta_processor = MetricDeltaProcessor.new(
          hvar: @hvar,
          vvar: @vvar,
          mvar: @mvar,
          config: @config,
        )
      end

      # Load a font table
      #
      # @param tag [String] Table tag
      # @return [Object, nil] Table object or nil
      def load_table(tag)
        return nil unless @font.respond_to?(:table_data)

        data = @font.table_data(tag)
        return nil if data.nil? || data.empty?

        # Map tag to table class
        table_class = case tag
                      when "fvar" then Tables::Fvar
                      when "gvar" then Tables::Gvar
                      when "HVAR" then Tables::Hvar
                      when "VVAR" then Tables::Vvar
                      when "MVAR" then Tables::Mvar
                      else return nil
                      end

        table_class.read(data)
      rescue StandardError => e
        warn "Failed to load #{tag} table: #{e.message}" if @config.dig(
          :validation, :validate_tables
        )
        nil
      end

      # Get variation region list from available tables
      #
      # @return [VariationCommon::VariationRegionList, nil] Region list
      def get_variation_region_list
        # Try to get from HVAR first (most common)
        if @hvar&.item_variation_store
          return @hvar.item_variation_store.variation_region_list
        end

        # Try VVAR
        if @vvar.respond_to?(:item_variation_store) && @vvar.item_variation_store
          return @vvar.item_variation_store.variation_region_list
        end

        # Try MVAR
        if @mvar&.item_variation_store
          return @mvar.item_variation_store.variation_region_list
        end

        nil
      end
    end
  end
end
