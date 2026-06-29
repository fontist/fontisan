# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `head` table from a UFO Font.
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/head
      module Head
        MAGIC_NUMBER = 0x5F0F3CF5
        DEFAULT_FLAGS = 0x000B
        DEFAULT_LOWEST_REC_PPEM = 8
        DEFAULT_FONT_DIRECTION_HINT = 2
        DEFAULT_GLYPH_DATA_FORMAT = 0
        LOCA_FORMAT_SHORT = 0
        LOCA_FORMAT_LONG = 1
        MAC_STYLE_REGULAR = 0
        # Seconds between 1904-01-01 (Mac epoch) and 1970-01-01 (Unix epoch)
        MAC_EPOCH_OFFSET = 2_082_844_800

        # @param font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] (unused here;
        #   bbox is computed by the caller for performance)
        # @return [Fontisan::Tables::Head]
        def self.build(font, glyphs:, units_per_em: nil, loca_format: LOCA_FORMAT_LONG)
          bbox = font_bbox(font, glyphs)
          Fontisan::Tables::Head.new(
            version_raw: 0x00010000,
            font_revision_raw: font_revision_fixed(font),
            checksum_adjustment: 0, # patched by FontWriter
            magic_number: MAGIC_NUMBER,
            flags: DEFAULT_FLAGS,
            units_per_em: units_per_em || font.info.units_per_em || 1000,
            created_raw: time_to_longdatetime(font.info.created),
            modified_raw: time_to_longdatetime(font.info.modified),
            x_min: bbox[:x_min].to_i,
            y_min: bbox[:y_min].to_i,
            x_max: bbox[:x_max].to_i,
            y_max: bbox[:y_max].to_i,
            mac_style: MAC_STYLE_REGULAR,
            lowest_rec_ppem: DEFAULT_LOWEST_REC_PPEM,
            font_direction_hint: DEFAULT_FONT_DIRECTION_HINT,
            index_to_loc_format: loca_format,
            glyph_data_format: DEFAULT_GLYPH_DATA_FORMAT,
          )
        end

        # Union bbox of every glyph's outline.
        def self.font_bbox(_font, glyphs)
          return { x_min: 0, y_min: 0, x_max: 0, y_max: 0 } if glyphs.empty?

          bboxes = glyphs.filter_map(&:bbox)
          return { x_min: 0, y_min: 0, x_max: 0, y_max: 0 } if bboxes.empty?

          {
            x_min: bboxes.map(&:x_min).min,
            y_min: bboxes.map(&:y_min).min,
            x_max: bboxes.map(&:x_max).max,
            y_max: bboxes.map(&:y_max).max,
          }
        end
        private_class_method :font_bbox

        # Parse the UFO version string ("1.0" or "Version 1.0") into
        # a 16.16 fixed-point int. Defaults to 1.0 on parse failure.
        def self.font_revision_fixed(font)
          version = [font.info.version_major, font.info.version_minor].compact
          return 0x00010000 if version.empty?

          major = font.info.version_major || 1
          minor = font.info.version_minor || 0
          ((major & 0xFFFF) << 16) | (minor & 0xFFFF)
        end
        private_class_method :font_revision_fixed

        # UFO 3 stores `openTypeHeadCreated` as "YYYY/MM/DD HH:MM:SS".
        # OpenType head.created/modified are LONGDATETIME seconds
        # since 1904-01-01. If the UFO field is absent, use now.
        def self.time_to_longdatetime(value)
          return Time.now.to_i + MAC_EPOCH_OFFSET if value.nil?

          require "time"
          parsed = nil
          begin
            parsed = Time.iso8601(value.to_s)
          rescue ArgumentError
            begin
              parsed = Time.parse(value.to_s)
            rescue ArgumentError
              parsed = Time.now
            end
          end
          parsed.to_i + MAC_EPOCH_OFFSET
        end
        private_class_method :time_to_longdatetime
      end
    end
  end
end
