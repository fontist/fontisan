# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # Licensing + embedding permissions + vendor provenance.
      #
      # Returned fields:
      #   licensing: Models::Audit::Licensing instance, or nil for Type 1
      #
      # Type 1 fonts have no OS/2 table; their licensing is nil. WOFF/
      # WOFF2 carry the same OS/2 + name tables as TTF/OTF and need no
      # special handling.
      class Licensing < Base
        # nameID → AuditReport field name, per OpenType name table spec.
        NAME_IDS = {
          copyright: 0,
          trademark: 7,
          manufacturer: 8,
          designer: 9,
          description: 10,
          vendor_url: 11,
          designer_url: 12,
          license_description: 13,
          license_url: 14,
        }.freeze
        private_constant :NAME_IDS

        def extract(context)
          font = context.font
          return { licensing: nil } unless sfnt?(font)

          os2 = os2_for(font)
          name = name_table_for(font)

          {
            licensing: Models::Audit::Licensing.new(
              **name_fields(name),
              vendor_id: sanitized_vendor_id(os2),
              embedding_type: Models::Audit::EmbeddingType.decode(os2&.fs_type&.to_i),
              fs_selection_flags: Models::Audit::FsSelectionFlags.decode(os2&.fs_selection&.to_i),
            ),
          }
        end

        private

        def sfnt?(font)
          font.is_a?(SfntFont)
        end

        def os2_for(font)
          return nil unless font.has_table?(Constants::OS2_TAG)

          font.table(Constants::OS2_TAG)
        end

        def name_table_for(font)
          return nil unless font.has_table?(Constants::NAME_TAG)

          font.table(Constants::NAME_TAG)
        end

        def name_fields(name)
          return {} unless name

          NAME_IDS.transform_values { |id| name.english_name(id) }
        end

        def sanitized_vendor_id(os2)
          raw = os2&.ach_vend_id
          return nil if raw.nil?

          raw.gsub(/[\x00\s]+$/, "")
        end
      end
    end
  end
end
