# frozen_string_literal: true

require_relative "../models/hint"
require "json"

module Fontisan
  module Hints
    # Applies rendering hints to PostScript/CFF font tables
    #
    # This applier validates and applies PostScript hint data to CFF fonts by
    # rebuilding the entire CFF table structure with updated Private DICT parameters.
    #
    # **Status**: Fully Operational (Phase 10A Complete)
    #
    # **PostScript Hint Parameters (Private DICT)**:
    #
    # - blue_values: Alignment zones for overshoot suppression
    # - other_blues: Additional alignment zones
    # - std_hw: Standard horizontal stem width
    # - std_vw: Standard vertical stem width
    # - stem_snap_h: Horizontal stem snap widths
    # - stem_snap_v: Vertical stem snap widths
    # - blue_scale, blue_shift, blue_fuzz: Overshoot parameters
    # - force_bold: Force bold flag
    # - language_group: Language group (0=Latin, 1=CJK)
    #
    # @example Apply PostScript hints
    #   applier = PostScriptHintApplier.new
    #   tables = { "CFF " => cff_table }
    #   hint_set = HintSet.new(format: "postscript", private_dict_hints: hints_json)
    #   result = applier.apply(hint_set, tables)
    class PostScriptHintApplier
      # Apply PostScript hints to font tables
      #
      # Validates hint data and rebuilds CFF table with updated Private DICT.
      # Supports arbitrary Private DICT size changes through full table reconstruction.
      # Also supports per-glyph hints injected directly into CharStrings.
      #
      # @param hint_set [HintSet] Hint data to apply
      # @param tables [Hash] Font tables (must include "CFF " or "CFF2 ")
      # @return [Hash] Updated font tables with hints applied
      def apply(hint_set, tables)
        return tables if hint_set.nil? || hint_set.empty?
        return tables unless hint_set.format == "postscript"

        if cff2_table?(tables)
          apply_cff2_hints(hint_set, tables)
        elsif cff_table?(tables)
          apply_cff_hints(hint_set, tables)
        else
          tables
        end
      end

      private

      # Check if tables contain CFF2 table
      #
      # @param tables [Hash] Font tables
      # @return [Boolean] True if CFF2 table present
      def cff2_table?(tables)
        tables.key?("CFF2") || tables.key?("CFF2 ")
      end

      # Check if tables contain CFF table
      #
      # @param tables [Hash] Font tables
      # @return [Boolean] True if CFF table present
      def cff_table?(tables)
        tables.key?("CFF ")
      end

      # Apply hints to CFF2 variable font
      #
      # @param hint_set [HintSet] Hint set with font-level and per-glyph hints
      # @param tables [Hash] Font tables
      # @return [Hash] Updated tables
      def apply_cff2_hints(hint_set, tables)
        # Load CFF2 table
        cff2_data = tables["CFF2"] || tables["CFF2 "]

        begin
          require_relative "../tables/cff2/table_reader"
          require_relative "../tables/cff2/table_builder"

          reader = Tables::Cff2::TableReader.new(cff2_data)

          # Validate CFF2 version
          reader.read_header
          unless reader.header[:major_version] == 2
            warn "Invalid CFF2 table version: #{reader.header[:major_version]}"
            return tables
          end

          # Build with hints
          builder = Tables::Cff2::TableBuilder.new(reader, hint_set)
          modified_table = builder.build

          # Update tables
          table_key = tables.key?("CFF2") ? "CFF2" : "CFF2 "
          tables[table_key] = modified_table

          tables
        rescue StandardError => e
          warn "Error applying CFF2 hints: #{e.message}"
          tables
        end
      end

      # Apply hints to CFF font
      #
      # @param hint_set [HintSet] Hint set with font-level and per-glyph hints
      # @param tables [Hash] Font tables
      # @return [Hash] Updated tables
      def apply_cff_hints(hint_set, tables)
        return tables unless tables["CFF "]

        # Validate hint parameters (Private DICT)
        hint_params = parse_hint_parameters(hint_set)

        # Check if we have per-glyph hints
        has_per_glyph_hints = hint_set.hinted_glyph_count.positive?

        # If neither font-level nor per-glyph hints, return unchanged
        return tables unless hint_params || has_per_glyph_hints

        # Validate font-level parameters if present
        if hint_params && !valid_hint_parameters?(hint_params)
          return tables
        end

        # Apply hints (both font-level and per-glyph)
        begin
          require_relative "../tables/cff/table_builder"
          require_relative "../tables/cff/charstring_rebuilder"
          require_relative "../tables/cff/hint_operation_injector"

          # Prepare per-glyph hint data if present
          per_glyph_hints = if has_per_glyph_hints
                              extract_per_glyph_hints(hint_set)
                            else
                              nil
                            end

          new_cff_data = Tables::Cff::TableBuilder.rebuild(
            tables["CFF "],
            private_dict_hints: hint_params,
            per_glyph_hints: per_glyph_hints
          )

          tables["CFF "] = new_cff_data
          tables
        rescue StandardError => e
          warn "Failed to apply PostScript hints: #{e.message}"
          tables
        end
      end

      # Parse hint parameters from HintSet
      #
      # @param hint_set [HintSet] Hint set with Private dict hints
      # @return [Hash, nil] Parsed hint parameters, or nil if invalid
      def parse_hint_parameters(hint_set)
        return nil unless hint_set.private_dict_hints
        return nil if hint_set.private_dict_hints == "{}"

        JSON.parse(hint_set.private_dict_hints)
      rescue JSON::ParserError => e
        warn "Failed to parse Private dict hints: #{e.message}"
        nil
      end

      # Validate hint parameters against CFF specification limits
      #
      # @param params [Hash] Hint parameters
      # @return [Boolean] True if all parameters are valid
      def valid_hint_parameters?(params)
        # Validate blue values (must be pairs, max 7 pairs = 14 values)
        if params["blue_values"] || params[:blue_values]
          values = params["blue_values"] || params[:blue_values]
          return false unless values.is_a?(Array)
          return false if values.length > 14  # Max 7 pairs
          return false if values.length.odd?  # Must be pairs
        end

        # Validate other_blues (max 5 pairs = 10 values)
        if params["other_blues"] || params[:other_blues]
          values = params["other_blues"] || params[:other_blues]
          return false unless values.is_a?(Array)
          return false if values.length > 10
          return false if values.length.odd?
        end

        # Validate stem widths (single values)
        if params["std_hw"] || params[:std_hw]
          value = params["std_hw"] || params[:std_hw]
          return false unless value.is_a?(Numeric)
          return false if value.negative?
        end

        if params["std_vw"] || params[:std_vw]
          value = params["std_vw"] || params[:std_vw]
          return false unless value.is_a?(Numeric)
          return false if value.negative?
        end

        # Validate stem snaps (arrays, max 12 values each)
        %w[stem_snap_h stem_snap_v].each do |key|
          next unless params[key] || params[key.to_sym]

          values = params[key] || params[key.to_sym]
          return false unless values.is_a?(Array)
          return false if values.length > 12
        end

        # Validate blue_scale (should be positive)
        if params["blue_scale"] || params[:blue_scale]
          value = params["blue_scale"] || params[:blue_scale]
          return false unless value.is_a?(Numeric)
          return false if value <= 0
        end

        # Validate language_group (0 or 1 only)
        if params["language_group"] || params[:language_group]
          value = params["language_group"] || params[:language_group]
          return false unless [0, 1].include?(value)
        end

        true
      end

      # Extract specific hint parameter with symbol/string key support
      #
      # @param params [Hash] Hint parameters
      # @param key [String] Parameter name
      # @return [Object, nil] Parameter value
      def extract_param(params, key)
        params[key] || params[key.to_sym]
      end

      # Extract per-glyph hint data from HintSet
      #
      # @param hint_set [HintSet] Hint set with per-glyph hints
      # @return [Hash] Hash mapping glyph_id => Array<Hint>
      def extract_per_glyph_hints(hint_set)
        per_glyph = {}

        hint_set.hinted_glyph_ids.each do |glyph_id|
          hints = hint_set.get_glyph_hints(glyph_id)
          per_glyph[glyph_id.to_i] = hints unless hints.empty?
        end

        per_glyph
      end
    end
  end
end
