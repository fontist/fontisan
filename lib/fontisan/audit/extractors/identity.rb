# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # Identity fields: the human-readable names a font uses to describe
      # itself, drawn from the `name` table (SFNT) or font dictionary
      # (Type 1).
      #
      # Returned fields:
      #   family_name, subfamily_name, full_name, postscript_name,
      #   version, font_revision
      class Identity < Base
        def extract(context)
          if context.font.is_a?(Type1Font)
            type1_identity(context.font)
          else
            sfnt_identity(context.font)
          end
        end

        private

        def sfnt_identity(font)
          name_table = font.table(Constants::NAME_TAG) if font.has_table?(Constants::NAME_TAG)
          head_table = font.table(Constants::HEAD_TAG) if font.has_table?(Constants::HEAD_TAG)

          {
            family_name: name_table&.english_name(Tables::Name::FAMILY),
            subfamily_name: name_table&.english_name(Tables::Name::SUBFAMILY),
            full_name: name_table&.english_name(Tables::Name::FULL_NAME),
            postscript_name: name_table&.english_name(Tables::Name::POSTSCRIPT_NAME),
            version: name_table&.english_name(Tables::Name::VERSION),
            font_revision: head_table&.font_revision,
          }
        end

        def type1_identity(font)
          font_info = font.font_dictionary&.font_info
          {
            family_name: font_info&.family_name,
            subfamily_name: nil,
            full_name: font_info&.full_name,
            postscript_name: font.font_name,
            version: font_info&.version,
            font_revision: nil,
          }
        end
      end
    end
  end
end
