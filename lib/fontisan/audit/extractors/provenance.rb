# frozen_string_literal: true

require "digest"
require "time"

module Fontisan
  module Audit
    module Extractors
      # Provenance fields: who generated this report, when, from what.
      #
      # Returned fields:
      #   generated_at, fontisan_version, source_file, source_sha256,
      #   source_format, font_index, num_fonts_in_source
      class Provenance < Base
        def extract(context)
          {
            generated_at: Time.now.utc.iso8601,
            fontisan_version: Fontisan::VERSION,
            source_file: File.expand_path(context.font_path),
            source_sha256: Digest::SHA256.file(context.font_path).hexdigest,
            source_format: context.source_format,
            font_index: context.font_index,
            num_fonts_in_source: context.num_fonts_in_source,
          }
        end
      end
    end
  end
end
