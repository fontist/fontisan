# frozen_string_literal: true

module Fontisan
  module Type1
    # PFB (Printer Font Binary) Generator
    #
    # Generates the canonical Adobe Type 1 PFB from a TrueType font:
    # every glyph is converted through {TTFToType1Converter} (quadratic
    # curves become cubics), the CharStrings are encrypted per glyph, and
    # {PFBWriter} assembles the three-segment file. Output is deterministic:
    # no random bytes, no timestamps, no UUIDs.
    #
    # @example Generate PFB from TTF
    #   font = Fontisan::FontLoader.load("font.ttf")
    #   pfb_data = Fontisan::Type1::PFBGenerator.generate(font)
    #   File.binwrite("font.pfb", pfb_data)
    #
    # @example Generate PFB with custom options
    #   options = { upm_scale: 1000 }
    #   pfb_data = Fontisan::Type1::PFBGenerator.generate(font, options)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5178.Type1.pdf
    class PFBGenerator
      # @option options [Integer, :native] :upm_scale Target UPM (default: 1000)
      # @option options [Class] :encoding Encoding class (default: Encodings::AdobeStandard)
      # @option options [Boolean] :convert_curves Convert quadratic to cubic (default: true)
      def self.generate(font, options = {})
        new(font, options).generate
      end

      def initialize(font, options = {})
        @font = font
        @options = options
        @metrics = MetricsCalculator.new(font)

        upm_scale = options[:upm_scale] || 1000
        @scaler = if upm_scale == :native
                    UPMScaler.native(font)
                  else
                    UPMScaler.new(font, target_upm: upm_scale)
                  end

        @encoding = options[:encoding] || Encodings::AdobeStandard
        @convert_curves = options.fetch(:convert_curves, true)
      end

      # Generate PFB file content
      #
      # @return [String] PFB binary content
      def generate
        PFBWriter.new(
          psname: psname,
          version: version,
          fontinfo: fontinfo,
          bbox: scaled_bbox,
          private_entries: private_entries,
          charstrings: named_charstrings,
        ).write
      end

      private

      def psname
        @font.post_script_name || "Untitled"
      end

      def version
        name_table = @font.table(Constants::NAME_TAG)
        return "1.0" unless name_table

        name_table.english_name(Tables::Name::VERSION) || "1.0"
      end

      def fontinfo
        info = { version: version, FullName: full_name, FamilyName: family_name,
                 Weight: weight, ItalicAngle: italic_angle, isFixedPitch: fixed_pitch? }
        name_table = @font.table(Constants::NAME_TAG)
        if name_table
          copyright = name_table.english_name(Tables::Name::COPYRIGHT)
          info[:Copyright] = copyright if copyright
        end
        if post_table&.underline_position
          info[:UnderlinePosition] = @scaler.scale(post_table.underline_position)
          info[:UnderlineThickness] = @scaler.scale(post_table.underline_thickness)
        end
        info
      end

      def post_table = @font.table(Constants::POST_TAG)

      def full_name
        name_table = @font.table(Constants::NAME_TAG)
        return psname unless name_table

        name_table.english_name(Tables::Name::FULL_NAME) || psname
      end

      def family_name
        name_table = @font.table(Constants::NAME_TAG)
        return psname unless name_table

        name_table.english_name(Tables::Name::FAMILY) || psname
      end

      def weight
        os2 = @font.table(Constants::OS2_TAG)
        return "Regular" unless os2.respond_to?(:weight_class) && os2.weight_class

        WEIGHT_NAMES[(os2.weight_class / 100).clamp(1, 9)] || "Regular"
      end

      WEIGHT_NAMES = {
        1 => "Thin", 2 => "ExtraLight", 3 => "Light", 4 => "Regular",
        5 => "Medium", 6 => "SemiBold", 7 => "Bold", 8 => "ExtraBold", 9 => "Black"
      }.freeze

      def italic_angle
        post_table&.italic_angle.to_f
      end

      def fixed_pitch?
        (post_table&.is_fixed_pitch || 0) != 0
      end

      def scaled_bbox
        head = @font.table(Constants::HEAD_TAG)
        return [0, 0, 0, 0] unless head

        [
          @scaler.scale(head.x_min || 0),
          @scaler.scale(head.y_min || 0),
          @scaler.scale(head.x_max || 1000),
          @scaler.scale(head.y_max || 1000),
        ]
      end

      # The Private dictionary entries, derived from the source metrics.
      def private_entries
        entries = {
          "BlueValues" => [0, 0],
          "password" => 5839,
          "MinFeature" => "{16 16}",
        }
        os2 = @font.table(Constants::OS2_TAG)
        if os2.respond_to?(:us_weight_class) && os2.us_weight_class
          stem = @scaler.scale([100, 80, 90][os2.us_weight_class / 100] || 80)
          entries["StdHW"] = stem
          entries["StdVW"] = stem
          entries["ForceBold"] = os2.us_weight_class >= 700
        end
        entries
      end

      # GID-keyed plain CharStrings from the converter, renamed via the post
      # table (falling back to glyphN for unnamed glyphs).
      def named_charstrings
        plain = if @convert_curves
                  TTFToType1Converter.convert(@font, @scaler, @encoding)
                else
                  {}
                end
        names = post_table&.glyph_names || []
        plain.filter_map do |gid, charstring|
          name = names[gid] || "glyph#{gid}"
          [name, charstring] unless charstring.empty?
        end.to_h
      end
    end
  end
end
