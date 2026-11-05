# frozen_string_literal: true

# Derives a WOFF2 collection (no public source exists) by encoding the
# 4-member derived TTC with fontisan's Woff2::CollectionEncoder. The output is
# committed because brotli output is not reproducible across builds. CI
# cross-checks it with the pinned Google woff2_decompress
# (`rake corpus:check_woff2`), so it is not Ruby checking itself.
#
#   bundle exec ruby corpus/derive/woff2_collection.rb [OUTPUT_DIR]
require "fontisan"
require_relative "common"

ttc = File.join(CorpusDerive::ROOT, "corpus", "derived", "ttc-4members-shared.ttc")
fonts = File.open(ttc, "rb") do |io|
  Fontisan::FontLoader.load_collection(ttc).extract_fonts(io)
end
bytes = Fontisan::Woff2::CollectionEncoder.new(brotli_quality: 11).encode_fonts(fonts)
CorpusDerive.write("woff2-collection-4members.woff2", bytes)
