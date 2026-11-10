# frozen_string_literal: true

# Derives a WOFF2 collection (no public source exists) by encoding the
# 4-member derived TTC with fontisan's Woff2::CollectionEncoder. The output is
# committed. The output is byte-reproducible: the only environment-dependent
# input was head.modified (the encoder stamps the clock when no timestamp is
# given), so the script pins it. CI cross-checks it with the pinned Google woff2_decompress
# (`rake corpus:check_woff2`), so it is not Ruby checking itself.
#
#   bundle exec ruby corpus/derive/woff2_collection.rb [OUTPUT_DIR]
require "fontisan"
require_relative "common"

ttc = File.join(CorpusDerive::ROOT, "corpus", "derived", "ttc-4members-shared.ttc")
fonts = File.open(ttc, "rb") do |io|
  Fontisan::FontLoader.load_collection(ttc).extract_fonts(io)
end
# Fixed head.modified (2026-01-01T00:00:00Z): later than every member's
# head.created, as Chrome's OTS requires, and independent of the clock.
MODIFIED = 1_767_225_600
bytes = Fontisan::Woff2::CollectionEncoder.new(brotli_quality: 11, timestamp: MODIFIED).encode_fonts(fonts)
CorpusDerive.write("woff2-collection-4members.woff2", bytes)
