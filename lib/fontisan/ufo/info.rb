# frozen_string_literal: true

module Fontisan
  module Ufo
    # Typed wrapper around a UFO's `fontinfo.plist`. Provides accessor
    # methods for every standard UFO 3 field, with sensible defaults
    # when reading a UFO that omits some fields.
    #
    # Field naming follows UFO 3 (camelCase in the plist, snake_case in
    # Ruby). Fields are looked up case-insensitively on read.
    class Info
      # Convenience: standard fields. Add to this list as new compiler
      # needs arise; serialization walks all known fields.
      STANDARD_FIELDS = %i[
        family_name style_name version_major version_minor units_per_em
        ascender descender cap_height x_height italic_angle
        postscript_font_name postscript_full_name postscript_weight_name
        copyright created modified note
        open_type_head_created open_type_head_flags
        open_type_hhea_ascender open_type_hhea_descender
        open_type_hhea_line_gap open_type_name_records
        open_type_os2_weight_class open_type_os2_width_class
        open_type_vhea_ascender open_type_vhea_descender open_type_vhea_line_gap
        year_month_day_time_seconds_since_epoch
      ].freeze

      attr_accessor(*STANDARD_FIELDS)

      # Catch-all for non-standard (vendor-specific) fields.
      attr_accessor :extras

      def initialize(values = {})
        @extras = {}
        values.each do |key, value|
          attr = camel_to_snake(key.to_s).to_sym
          if STANDARD_FIELDS.include?(attr)
            public_send("#{attr}=", value)
          else
            @extras[key.to_s] = value
          end
        end
      end

      # @return [Hash] a Hash<String, Object> suitable for emit() to
      #   serialize back to plist. Keys are in camelCase per UFO 3.
      def to_plist
        h = {}
        STANDARD_FIELDS.each do |attr|
          value = public_send(attr)
          h[snake_to_camel(attr.to_s)] = value unless value.nil?
        end
        @extras.each { |k, v| h[k] = v }
        h
      end

      # ---------- case conversion ----------

      # "familyName"            -> "family_name"
      # "openTypeOS2WeightClass" -> "open_type_os2_weight_class"
      # "OTTO"                   -> "otto"
      def camel_to_snake(str)
        str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end

      # "family_name"            -> "familyName"
      # "open_type_hhea_ascender" -> "openTypeHheaAscender"
      # "version_major"           -> "versionMajor"
      def snake_to_camel(str)
        parts = str.split("_")
        return str if parts.size <= 1

        parts[0] + parts[1..].map(&:capitalize).join
      end
      private :camel_to_snake, :snake_to_camel
    end
  end
end
