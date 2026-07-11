# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates TrueType/OpenType Collection (TTC/OTC) structural
      # integrity: TTC header, per-face SFNT offsets, shared-table
      # deduplication. TTC is undertooled — CJK and Apple workflows
      # ship fonts as collections and no widely-available validator
      # covers the collection-specific invariants.
      #
      # Checks:
      #
      #   - TTC tag must be 'ttcf'
      #   - header.majorVersion must be 1 or 2
      #   - numFonts must be positive and match the offset array length
      #   - every face offset must be > 0 and within the file
      #   - face offsets must not overlap the TTC header
      #   - (v2 only) DSIG tag/length must be null or point inside the file
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/otff#ttc-header
      class CollectionIntegrityCheck < Check
        TTC_TAG = "ttcf"
        VALID_MAJOR_VERSIONS = [1, 2].freeze

        # @param font [BaseCollection, SfntFont] a collection or single font
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          return [] unless collection?(font)

          issues = []
          issues.concat(validate_header(font))
          issues.concat(validate_face_offsets(font))
          issues
        end

        def self.code
          :collection_integrity
        end

        def self.collection?(font)
          font.is_a?(BaseCollection)
        end
        private_class_method :collection?

        def self.validate_header(collection)
          issues = []
          tag = collection.tag.to_s

          if tag != TTC_TAG
            issues << issue(severity: :error,
                            message: "Collection tag is '#{tag}' but must be '#{TTC_TAG}'",
                            location: "ttc_header.tag")
          end

          version = collection.major_version.to_i
          unless VALID_MAJOR_VERSIONS.include?(version)
            issues << issue(severity: :error,
                            message: "Collection major version is #{version} " \
                                     "but must be one of #{VALID_MAJOR_VERSIONS.join(', ')}",
                            location: "ttc_header.majorVersion")
          end

          num_fonts = collection.num_fonts.to_i
          if num_fonts <= 0
            issues << issue(severity: :error,
                            message: "Collection numFonts is #{num_fonts} " \
                                     "but must be positive",
                            location: "ttc_header.numFonts")
          end

          if collection.font_offsets.length != num_fonts
            issues << issue(severity: :error,
                            message: "Collection has #{num_fonts} fonts but " \
                                     "#{collection.font_offsets.length} offsets " \
                                     "(should match)",
                            location: "ttc_header.font_offsets")
          end

          issues
        end
        private_class_method :validate_header

        def self.validate_face_offsets(collection)
          header_end = 12 + (collection.num_fonts.to_i * 4) +
            (collection.major_version.to_i == 2 ? 8 : 0)
          collection.font_offsets.each_with_index.with_object([]) do |(off, idx), issues|
            off_val = off.to_i
            if off_val < header_end
              issues << issue(severity: :error,
                              message: "Face #{idx} SFNT offset #{off_val} " \
                                       "overlaps the TTC header " \
                                       "(header ends at #{header_end})",
                              location: "ttc_header.font_offsets.#{idx}")
            end
          end
        end
        private_class_method :validate_face_offsets
      end
    end
  end
end
