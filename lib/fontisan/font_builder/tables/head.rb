# frozen_string_literal: true

module Fontisan
  module FontBuilder
    module Tables
      # Serializes the OpenType +head+ table. 54 bytes total.
      #
      # Spec: https://learn.microsoft.com/en-us/typography/opentype/spec/head
      class Head
        MAGIC_NUMBER = 0x5F0F3CF5
        DEFAULT_FLAGS = 0x000B
        DEFAULT_LOWEST_REC_PPEM = 8
        DEFAULT_FONT_DIRECTION_HINT = 2
        DEFAULT_GLYPH_DATA_FORMAT = 0
        MAC_EPOCH_OFFSET = 2_082_844_800 # seconds 1904-01-01 → 1970-01-01

        attr_reader :model

        def initialize(model)
          @model = model
        end

        # @return [String] 54-byte binary
        def bytes
          [
            1, 0,                              # majorVersion, minorVersion
            font_revision_fixed,               # fontRevision (Fixed 16.16)
            0,                                 # checkSumAdjustment (patched by Assembler)
            MAGIC_NUMBER,
            DEFAULT_FLAGS,
            model.units_per_em,
            time_to_long_date_time(model.created),
            time_to_long_date_time(model.modified),
            x_min, y_min, x_max, y_max,
            0,                                 # macStyle: regular
            DEFAULT_LOWEST_REC_PPEM,
            DEFAULT_FONT_DIRECTION_HINT,
            loc_format,
            DEFAULT_GLYPH_DATA_FORMAT
          ].pack("nnNNNnnq>q>nnnnnnnnn")
        end

        private

        def font_revision_fixed
          m = model.font_version.match(/(\d+)\.(\d+)/)
          return 0x00010000 unless m

          (m[1].to_i << 16) | (m[2].to_i & 0xFFFF)
        end

        def time_to_long_date_time(unix_seconds)
          unix_seconds.to_i + MAC_EPOCH_OFFSET
        end

        def x_min; 0; end
        def y_min; 0; end
        def x_max; 0; end
        def y_max; 0; end

        def loc_format; 1; end # 1 = long offsets
      end
    end
  end
end
