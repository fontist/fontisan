# frozen_string_literal: true

require_relative "interpolator"
require_relative "region_matcher"
require_relative "table_accessor"

module Fontisan
  module Variation
    # Applies metrics variation deltas to font metrics tables
    #
    # This class handles applying variation deltas from HVAR, VVAR, and MVAR
    # tables to the corresponding metrics tables (hmtx, vmtx, head, hhea, etc.).
    #
    # Process:
    # 1. Parse ItemVariationStore from HVAR/VVAR/MVAR
    # 2. Calculate scalars for current coordinates using regions
    # 3. Apply deltas to base metrics
    # 4. Update metrics tables with adjusted values
    #
    # @example Applying HVAR deltas
    #   adjuster = MetricsAdjuster.new(font, interpolator)
    #   adjuster.apply_hvar_deltas({ "wght" => 700.0 })
    class MetricsAdjuster
      include TableAccessor

      # @return [TrueTypeFont, OpenTypeFont] Font instance
      attr_reader :font

      # @return [Interpolator] Coordinate interpolator
      attr_reader :interpolator

      # Initialize metrics adjuster
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font instance
      # @param interpolator [Interpolator] Coordinate interpolator
      def initialize(font, interpolator)
        @font = font
        @interpolator = interpolator
        @variation_tables = {}
      end

      # Apply HVAR deltas to horizontal metrics
      #
      # @param coordinates [Hash<String, Float>] Design space coordinates
      # @return [Boolean] True if deltas were applied
      def apply_hvar_deltas(coordinates)
        return false unless has_variation_table?("HVAR")
        return false unless has_variation_table?("hmtx")

        hvar = variation_table("HVAR")
        return false unless hvar&.item_variation_store

        # Parse region list and calculate scalars
        regions = extract_regions_from_store(hvar.item_variation_store)
        return false if regions.empty?

        scalars = @interpolator.calculate_scalars(coordinates, regions)

        # Get hmtx table
        hmtx = variation_table("hmtx")
        return false unless hmtx&.parsed?

        # Get glyph count
        maxp = variation_table("maxp")
        glyph_count = maxp ? maxp.num_glyphs : 0
        return false if glyph_count.zero?

        # Apply deltas to each glyph
        adjusted_metrics = apply_horizontal_metrics_deltas(
          hvar, hmtx, glyph_count, scalars
        )

        # Rebuild hmtx table with adjusted metrics
        rebuild_hmtx_table(adjusted_metrics)

        true
      end

      # Apply VVAR deltas to vertical metrics
      #
      # @param coordinates [Hash<String, Float>] Design space coordinates
      # @return [Boolean] True if deltas were applied
      def apply_vvar_deltas(coordinates)
        return false unless has_variation_table?("VVAR")
        return false unless has_variation_table?("vmtx")

        vvar = variation_table("VVAR")
        return false unless vvar&.item_variation_store

        # Parse region list and calculate scalars
        regions = extract_regions_from_store(vvar.item_variation_store)
        return false if regions.empty?

        @interpolator.calculate_scalars(coordinates, regions)

        # Apply deltas to vmtx
        # Similar to HVAR but for vertical metrics
        # Placeholder for full implementation

        true
      end

      # Apply MVAR deltas to font-wide metrics
      #
      # @param coordinates [Hash<String, Float>] Design space coordinates
      # @return [Boolean] True if deltas were applied
      def apply_mvar_deltas(coordinates)
        return false unless has_variation_table?("MVAR")

        mvar = variation_table("MVAR")
        return false unless mvar&.item_variation_store

        # Parse region list and calculate scalars
        regions = extract_regions_from_store(mvar.item_variation_store)
        return false if regions.empty?

        scalars = @interpolator.calculate_scalars(coordinates, regions)

        # Apply deltas to each metric tag
        apply_font_wide_metrics_deltas(mvar, scalars)

        true
      end

      private

      # Extract regions from ItemVariationStore
      #
      # @param store [VariationCommon::ItemVariationStore] Variation store
      # @return [Array<Hash>] Array of region definitions
      def extract_regions_from_store(store)
        region_list = store.variation_region_list
        return [] unless region_list

        regions = []
        region_list.regions.each do |region_coords|
          region = {}
          region_coords.each_with_index do |axis_coords, axis_index|
            next if axis_index >= @interpolator.axes.length

            axis = @interpolator.axes[axis_index]
            region[axis.axis_tag] = {
              start: axis_coords.start,
              peak: axis_coords.peak,
              end: axis_coords.end_value,
            }
          end
          regions << region
        end

        regions
      end

      # Apply horizontal metrics deltas
      #
      # @param hvar [Hvar] HVAR table
      # @param hmtx [Hmtx] hmtx table
      # @param glyph_count [Integer] Number of glyphs
      # @param scalars [Array<Float>] Region scalars
      # @return [Array<Hash>] Adjusted metrics
      def apply_horizontal_metrics_deltas(hvar, hmtx, glyph_count, scalars)
        adjusted_metrics = []

        glyph_count.times do |glyph_id|
          base_metric = hmtx.metric_for(glyph_id)
          next unless base_metric

          # Get advance width deltas
          advance_deltas = hvar.advance_width_delta_set(glyph_id) || []
          lsb_deltas = hvar.lsb_delta_set(glyph_id) || []

          # Apply deltas using scalars
          new_advance = @interpolator.interpolate_value(
            base_metric[:advance_width],
            advance_deltas,
            scalars,
          ).round

          new_lsb = @interpolator.interpolate_value(
            base_metric[:lsb],
            lsb_deltas,
            scalars,
          ).round

          adjusted_metrics << {
            advance_width: new_advance,
            lsb: new_lsb,
          }
        end

        adjusted_metrics
      end

      # Apply font-wide metrics deltas
      #
      # @param mvar [Mvar] MVAR table
      # @param scalars [Array<Float>] Region scalars
      def apply_font_wide_metrics_deltas(mvar, scalars)
        # Get all metric tags
        mvar.metric_tags.each do |tag|
          delta_set = mvar.metric_delta_set(tag)
          next unless delta_set

          # Get base value for this metric
          base_value = get_base_metric_value(tag)
          next unless base_value

          # Apply deltas
          new_value = @interpolator.interpolate_value(
            base_value,
            delta_set,
            scalars,
          ).round

          # Update metric in appropriate table
          update_font_metric(tag, new_value)
        end
      end

      # Get base metric value by tag
      #
      # @param tag [String] Metric tag (e.g., "hasc", "hdsc")
      # @return [Integer, nil] Base metric value
      def get_base_metric_value(tag)
        case tag
        when "hasc"
          variation_table("hhea")&.ascender
        when "hdsc"
          variation_table("hhea")&.descender
        when "hlgp"
          variation_table("hhea")&.line_gap
        when "xhgt"
          os2 = variation_table("OS/2")
          os2&.s_x_height if os2.respond_to?(:s_x_height)
        when "cpht"
          os2 = variation_table("OS/2")
          os2&.s_cap_height if os2.respond_to?(:s_cap_height)
          # Add more metrics as needed
        end
      end

      # Update font metric in appropriate table
      #
      # @param tag [String] Metric tag
      # @param value [Integer] New metric value
      def update_font_metric(tag, value)
        # This is a placeholder - full implementation would:
        # 1. Modify the appropriate table's binary data
        # 2. Update the font's table data
        # For now, we just log the update
        # In production, this would rebuild the affected tables
      end

      # Rebuild hmtx table with adjusted metrics
      #
      # @param metrics [Array<Hash>] Adjusted metrics
      def rebuild_hmtx_table(metrics)
        # Build new hmtx binary data
        data = build_hmtx_data(metrics)

        # Update font's table data
        @font.table_data["hmtx"] = data if data
      end

      # Build hmtx binary data from metrics
      #
      # @param metrics [Array<Hash>] Metrics to encode
      # @return [String, nil] Binary data
      def build_hmtx_data(metrics)
        return nil if metrics.empty?

        # Find last unique advance width
        last_advance = metrics.last[:advance_width]
        number_of_h_metrics = metrics.length

        # Optimize: count from end while advance width is same
        (metrics.length - 1).downto(1) do |i|
          break if metrics[i][:advance_width] != last_advance

          number_of_h_metrics = i
        end

        # Build binary data
        data = String.new("", encoding: Encoding::BINARY)

        # Write hMetrics array
        number_of_h_metrics.times do |i|
          metric = metrics[i]
          data << [metric[:advance_width]].pack("n")  # uint16
          data << [metric[:lsb]].pack("n")            # int16 (as uint16, will be interpreted as signed)
        end

        # Write remaining LSBs
        (number_of_h_metrics...metrics.length).each do |i|
          data << [metrics[i][:lsb]].pack("n") # int16
        end

        # Update hhea's numberOfHMetrics
        update_hhea_number_of_h_metrics(number_of_h_metrics)

        data
      end

      # Update hhea table's numberOfHMetrics field
      #
      # @param count [Integer] New numberOfHMetrics value
      def update_hhea_number_of_h_metrics(count)
        return unless has_variation_table?("hhea")

        hhea = variation_table("hhea")
        return unless hhea

        # Update the field if hhea supports it
        hhea.number_of_h_metrics = count if hhea.respond_to?(:number_of_h_metrics=)
      end
    end
  end
end
