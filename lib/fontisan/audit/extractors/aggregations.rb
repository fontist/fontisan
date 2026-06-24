# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # Aggregation fields: UCD block/script coverage and the font's
      # OpenType script/feature inventory.
      #
      # Returned fields:
      #   ucd_version, blocks, unicode_scripts,
      #   opentype_scripts, features
      class Aggregations < Base
        def extract(context)
          ucd = context.ucd
          {
            **ucd_aggregations(context.codepoints, ucd),
            opentype_scripts: opentype_scripts(context.font),
            features: all_features(context.font),
          }
        end

        private

        def ucd_aggregations(codepoints, ucd)
          return empty_aggregation(ucd) if ucd[:blocks_index].nil?

          blocks_hashes = Ucd::Aggregator.aggregate_blocks(codepoints,
                                                           ucd[:blocks_index])
          {
            ucd_version: ucd[:version],
            blocks: blocks_hashes.map { |h| build_audit_block(h) },
            unicode_scripts: Ucd::Aggregator.aggregate_scripts(codepoints,
                                                               ucd[:scripts_index]),
          }
        end

        def empty_aggregation(ucd)
          { ucd_version: ucd[:version], blocks: [], unicode_scripts: [] }
        end

        def build_audit_block(block_hash)
          Models::Audit::AuditBlock.new(
            name: block_hash[:name],
            first_cp: block_hash[:first_cp],
            last_cp: block_hash[:last_cp],
            range: format("U+%<first>04X-U+%<last>04X",
                          first: block_hash[:first_cp], last: block_hash[:last_cp]),
            total: block_hash[:total],
            covered: block_hash[:covered],
            fill_ratio: block_hash[:fill_ratio],
            complete: block_hash[:complete],
          )
        end

        def opentype_scripts(font)
          scripts = Set.new
          scripts.merge(font.table(Constants::GSUB_TAG).scripts) if font.has_table?(Constants::GSUB_TAG)
          scripts.merge(font.table(Constants::GPOS_TAG).scripts) if font.has_table?(Constants::GPOS_TAG)
          scripts.sort
        end

        def all_features(font)
          features = Set.new
          scripts = opentype_scripts(font)

          if font.has_table?(Constants::GSUB_TAG)
            gsub = font.table(Constants::GSUB_TAG)
            scripts.each { |tag| features.merge(gsub.features(script_tag: tag)) }
          end

          if font.has_table?(Constants::GPOS_TAG)
            gpos = font.table(Constants::GPOS_TAG)
            scripts.each { |tag| features.merge(gpos.features(script_tag: tag)) }
          end

          features.sort
        end
      end
    end
  end
end
