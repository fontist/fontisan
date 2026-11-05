# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "fontisan"
require "json"
require "fileutils"

# Scan goldens for the reference corpus (fontist/fontisan#156 card 0f).
#
# One JSON file per manifest row (malformed included: scan never raises),
# written from Fontisan::Reference.scan with the path reduced to a basename:
#
#   corpus/goldens/scan/<id>.json         ci tier, committed
#   corpus/goldens/scan-large/<id>.json   large tier, generated in CI (nightly)
module ScanGoldens
  ROOT = File.expand_path("../..", __dir__)
  MANIFEST = File.join(ROOT, "corpus", "manifest.json")
  GOLDEN_DIRS = { "ci" => "scan", "large" => "scan-large" }.freeze
  SCHEMA = 1

  module_function

  def manifest
    JSON.parse(File.read(MANIFEST)).fetch("fonts")
  end

  def entries(tier)
    manifest.select { |f| f["tier"] == tier }.sort_by { |f| f["id"] }
  end

  def font_path(entry)
    dir = entry["type"] == "derived" ? "derived" : File.join("fonts", entry["id"])
    File.join(ROOT, "corpus", dir, entry["file"])
  end

  def golden_dir(tier)
    File.join(ROOT, "corpus", "goldens", GOLDEN_DIRS.fetch(tier))
  end

  def golden_path(tier, id)
    File.join(golden_dir(tier), "#{id}.json")
  end

  # Rows for one font as Reference.scan returns them, paths reduced to basenames.
  def rows(path)
    Fontisan::Reference.scan([path]).map { |row| row.merge("path" => File.basename(row["path"])) }
  end

  def golden(entry)
    Fontisan::Reference.canonical_json(
      "schema" => SCHEMA,
      "id" => entry["id"],
      "file" => entry["file"],
      "tier" => entry["tier"],
      "font_sha256" => entry.fetch("sha256"),
      "comparison_class" => "exact",
      "rows" => rows(font_path(entry)),
    )
  end

  def generate(tier)
    bad = %w[FONTISAN_MODE FONTISAN_LAZY].select { |k| ENV.key?(k) }
    raise "unset #{bad.join(', ')} before generating goldens" unless bad.empty?

    entries(tier).to_h { |e| [golden_path(tier, e["id"]), golden(e)] }
  end

  def write(tier)
    out = generate(tier)
    FileUtils.mkdir_p(golden_dir(tier))
    out.each { |path, bytes| File.binwrite(path, bytes) }
    out.size
  end

  # Compare fresh output with the committed goldens. Returns problem strings.
  def verify(tier)
    fresh = generate(tier)
    problems = fresh.filter_map do |path, bytes|
      rel = path.delete_prefix("#{ROOT}/")
      if !File.exist?(path)
        "missing golden #{rel}"
      elsif File.binread(path).force_encoding(bytes.encoding) != bytes
        "golden differs #{rel}"
      end
    end
    problems + stale(tier, fresh.keys)
  end

  def stale(tier, expected)
    Dir.glob(File.join(golden_dir(tier), "*.json")).reject { |p| expected.include?(p) }
      .map { |p| "stale golden #{p.delete_prefix("#{ROOT}/")} (no manifest font)" }
  end
end

if $PROGRAM_NAME == __FILE__
  tier = ARGV.fetch(0, "ci")
  puts "wrote #{ScanGoldens.write(tier)} scan goldens (tier #{tier})"
end
