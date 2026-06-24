# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # OpenType layout summary: union of GSUB + GPOS scripts and features,
      # plus a per-script breakdown preserving which feature belongs to
      # which script under which table.
      #
      # Returned fields:
      #   opentype_layout: Models::Audit::OpenTypeLayout, or nil for
      #                    Type 1
      #
      # Owned here (MECE split from Aggregations, which is UCD-only).
      class OpenTypeLayout < Base
        def extract(context)
          font = context.font
          return { opentype_layout: nil } unless sfnt?(font)

          gsub_scripts = scripts_in(font, Constants::GSUB_TAG)
          gpos_scripts = scripts_in(font, Constants::GPOS_TAG)
          all_scripts = (gsub_scripts + gpos_scripts).uniq.sort

          by_script = all_scripts.map do |tag|
            Models::Audit::ScriptFeatures.new(
              script: tag,
              gsub_features: features_for(font, Constants::GSUB_TAG, tag),
              gpos_features: features_for(font, Constants::GPOS_TAG, tag),
            )
          end

          { opentype_layout: Models::Audit::OpenTypeLayout.new(
            scripts: all_scripts,
            features: aggregate_features(by_script),
            by_script: by_script,
            has_gsub: font.has_table?(Constants::GSUB_TAG),
            has_gpos: font.has_table?(Constants::GPOS_TAG),
          ) }
        end

        protected

        def sfnt?(font)
          font.is_a?(SfntFont)
        end

        private

        def scripts_in(font, tag)
          return [] unless font.has_table?(tag)

          font.table(tag).scripts
        end

        def features_for(font, tag, script)
          return [] unless font.has_table?(tag)

          font.table(tag).features(script_tag: script).sort
        end

        def aggregate_features(by_script)
          gsub = by_script.flat_map(&:gsub_features)
          gpos = by_script.flat_map(&:gpos_features)
          (gsub + gpos).uniq.sort
        end
      end
    end
  end
end
