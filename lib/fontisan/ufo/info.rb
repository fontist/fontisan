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

      # Build a +Ufo::Info+ for one subfont of a collection. The family
      # name embeds the subfont name (e.g. +"MyFont CJK"+), and the
      # PostScript name uses the hyphenated form (e.g. +"MyFont-CJK"+).
      #
      # +version+ is parsed into +version_major+ / +version_minor+ per
      # the UFO major.minor shape (patch is dropped).
      #
      # +trademark+ is stored under +extras["openTypeNameTrademark"]+
      # because it is not in +STANDARD_FIELDS+ yet — see TODO 71
      # out-of-scope follow-up.
      #
      # @param family [String] collection-wide family name
      # @param subfont [String, Symbol] subfont identifier (appended to family)
      # @param version [String, Integer] e.g. "0.1", "1", "1.2.3"
      # @param subfamily [String] OpenType subfamily (default "Regular")
      # @param copyright [String, nil]
      # @param trademark [String, nil]
      # @return [Info]
      def self.for_subfont(family:, subfont:, version:,
                           subfamily: "Regular",
                           copyright: nil, trademark: nil)
        major, minor = parse_version(version)
        subfont_str = subfont.to_s
        values = {
          family_name: "#{family} #{subfont_str}",
          style_name: subfamily,
          version_major: major,
          version_minor: minor,
          postscript_font_name: "#{family}-#{subfont_str}",
          postscript_full_name: "#{family} #{subfont_str}",
        }
        values[:copyright] = copyright if copyright
        values["openTypeNameTrademark"] = trademark if trademark
        new(values)
      end

      # @param version [String, Integer]
      # @return [Array(Integer, Integer)] [major, minor]
      def self.parse_version(version)
        case version.to_s
        when /\A(\d+)\.(\d+)\.\d+\z/ then [Regexp.last_match(1).to_i,
                                           Regexp.last_match(2).to_i]
        when /\A(\d+)\.(\d+)\z/      then [Regexp.last_match(1).to_i,
                                           Regexp.last_match(2).to_i]
        when /\A(\d+)\z/             then [Regexp.last_match(1).to_i, 0]
        else [0, 0]
        end
      end
      private_class_method :parse_version

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
