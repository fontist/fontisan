# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "fontisan"
require "json"
require "digest"
require "fileutils"
require "tmpdir"

# Read goldens for the reference corpus (fontist/fontisan#156 card 0b).
#
# One JSON file per manifest font, written through Fontisan::Reference (the
# canonical serialisations are in docs/reference-facade.md):
#
#   corpus/goldens/read/<id>.json         ci tier, committed
#   corpus/goldens/read-large/<id>.json   large tier, generated in CI (nightly)
#
# A golden holds the `read` result for each loading mode and lazy flag
# (identical variants collapse to {"same_as" => key}), the `audit` result with
# and without --validate, and the known_reference_bug tags from
# corpus/TRIAGE.md. Malformed fonts belong to card 0e and are not covered here.
module CorpusGoldens
  ROOT = File.expand_path("../..", __dir__)
  MANIFEST = File.join(ROOT, "corpus", "manifest.json")
  GOLDEN_DIRS = { "ci" => "read", "large" => "read-large" }.freeze
  SWALLOW_DIR = File.join(ROOT, "corpus", "goldens", "read", "_swallow")
  MALFORMED = /\Amalformed-/
  VARIANTS = [[:metadata, true], [:metadata, false], [:full, true], [:full, false]].freeze
  SCHEMA = 1

  # TRIAGE.md ids of Ruby results that are kept as the reference (the golden
  # keeps Ruby's output and Rust reproduces it). Keyed by manifest id; "*"
  # applies to every font.
  KNOWN_REFERENCE_BUGS = {
    "fonttools-test-t1-pfb" => %w[T1-READ],
    "fonttools-test-t1-pfa" => %w[T1-READ],
    "fonttools-test-woff" => %w[WOFF-CHECKS],
    "fonttools-test-woff2" => %w[WOFF-CHECKS],
    "source-sans-3-regular-otf-woff" => %w[WOFF-CHECKS],
    "source-sans-3-regular-otf-woff2" => %w[WOFF-CHECKS],
    "source-sans-3-regular-ttf-woff" => %w[WOFF-CHECKS],
    "source-sans-3-regular-ttf-woff2" => %w[WOFF-CHECKS],
    "noto-sans-vf-wdth-wght" => %w[MVAR-OFFSET],
    "source-sans-3-vf-italic-ttf" => %w[MVAR-OFFSET],
    "source-sans-3-vf-upright-cff2" => %w[MVAR-OFFSET CFF2-PARSER],
    "source-sans-3-vf-upright-ttf" => %w[MVAR-OFFSET],
    "quirk-name-format-1" => %w[NAME-FORMAT1],
    "names-mac-roman-only" => %w[NAME-MAC-DECODE],
  }.freeze

  # NAME-FULL-REGULAR is derived: it applies to every font whose audit carries
  # the full-name message, so a new font cannot be missed.
  FULL_NAME_MESSAGE = /Full name .* doesn't match Family \+ Subfamily/
  FULL_NAME_TAG = "NAME-FULL-REGULAR"

  module_function

  def manifest
    JSON.parse(File.read(MANIFEST)).fetch("fonts")
  end

  def entries(tier)
    manifest.select { |f| f["tier"] == tier && !f["id"].match?(MALFORMED) }
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

  # Goldens are only meaningful with the loader's env overrides unset.
  def assert_clean_env!
    bad = %w[FONTISAN_MODE FONTISAN_LAZY].select { |k| ENV.key?(k) }
    raise "unset #{bad.join(', ')} before generating goldens" unless bad.empty?
  end

  # The error as data: class and message with the path reduced to a basename.
  def outcome(path)
    { "ok" => yield }
  rescue StandardError => e
    msg = e.message.gsub(path, File.basename(path)).gsub("#{File.dirname(path)}/", "")
    { "error" => { "class" => e.class.name, "message" => msg } }
  end

  def read_variants(path)
    seen = {}
    VARIANTS.each_with_object({}) do |(mode, lazy), out|
      key = "#{mode}/#{lazy ? 'lazy' : 'eager'}"
      result = outcome(path) { Fontisan::Reference.read(path, mode: mode, lazy: lazy) }
      comparable = strip_variant(result)
      out[key] = seen[comparable] ? { "same_as" => seen[comparable] } : result
      seen[comparable] ||= key
    end
  end

  # The variant itself is the key, so `mode` and `lazy` do not make otherwise
  # identical results differ.
  def strip_variant(result)
    return result unless result["ok"]

    { "ok" => result["ok"].map { |face| face.except("mode", "lazy") } }
  end

  def audit_variants(path)
    {
      "default" => outcome(path) { Fontisan::Reference.audit(path, validate: false) },
      "validate" => outcome(path) { Fontisan::Reference.audit(path, validate: true) },
    }
  end

  def reference_bugs(id, audit)
    tags = KNOWN_REFERENCE_BUGS.fetch(id, []).dup
    tags << FULL_NAME_TAG if JSON.generate(audit).match?(FULL_NAME_MESSAGE)
    tags.sort
  end

  def golden(entry, tier)
    path = font_path(entry)
    doc = {
      "schema" => SCHEMA,
      "id" => entry["id"],
      "file" => File.basename(path),
      "tier" => tier,
      "font_sha256" => entry.fetch("sha256"),
      "comparison_class" => "exact",
      "generated_in" => tier == "large" ? "ci" : "any",
      "read" => read_variants(path),
      "audit" => audit_variants(path),
    }
    doc["known_reference_bug"] = reference_bugs(entry["id"], doc["audit"])
    Fontisan::Reference.canonical_json(doc)
  end

  # Cases that hit the audit's error-swallowing paths on purpose, so a native
  # tier reproduces them: GSUB/GPOS scripts and features answer [] when the
  # table cannot be parsed (`collect_features`), and total_glyphs answers 0
  # when maxp cannot be read. Each is TestTTF with one table replaced; the
  # input font is committed next to its golden.
  SWALLOW_SOURCE = "fonttools-test-ttf"
  GARBAGE_LAYOUT = ([1, 0, 10, 10, 10].pack("n*") + ("\xFF".b * 6)).freeze
  SWALLOW_CASES = {
    "gsub-garbage" => ->(_tables) { { "GSUB" => GARBAGE_LAYOUT } },
    "gpos-garbage" => ->(_tables) { { "GPOS" => GARBAGE_LAYOUT } },
    "maxp-truncated" => ->(tables) { { "maxp" => tables.fetch("maxp").byteslice(0, 4) } },
  }.freeze

  # { path => bytes } for every swallow case: the input font and its golden.
  def swallow
    source = Fontisan::FontLoader.load(font_path(manifest.find { |e| e["id"] == SWALLOW_SOURCE }))
    tables = source.table_data
    SWALLOW_CASES.each_with_object({}) do |(name, change), out|
      font = Fontisan::FontWriter.write_font(tables.merge(change.call(tables)))
      input = File.join(SWALLOW_DIR, "#{name}.ttf")
      out[input] = font
      out[File.join(SWALLOW_DIR, "#{name}.json")] = swallow_golden(name, font)
    end
  end

  def swallow_golden(name, font)
    Dir.mktmpdir("swallow") do |dir|
      path = File.join(dir, "#{name}.ttf")
      File.binwrite(path, font)
      Fontisan::Reference.canonical_json(
        "schema" => SCHEMA, "case" => name, "source" => SWALLOW_SOURCE,
        "font_sha256" => Digest::SHA256.hexdigest(font), "comparison_class" => "exact",
        "known_reference_bug" => [],
        "read" => { "full/eager" => outcome(path) { Fontisan::Reference.read(path, mode: :full, lazy: false) } },
        "audit" => audit_variants(path)
      )
    end
  end

  # Every golden of a tier as { path => bytes }, generated fresh.
  def generate(tier)
    assert_clean_env!
    out = entries(tier).to_h { |e| [golden_path(tier, e["id"]), golden(e, tier)] }
    out.merge!(swallow) if tier == "ci"
    out
  end

  def write(tier)
    out = generate(tier)
    FileUtils.mkdir_p(golden_dir(tier))
    out.each do |path, bytes|
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
    end
    out.size
  end

  # Compare fresh output with the committed goldens. Returns problem strings.
  def verify(tier)
    problems = []
    fresh = generate(tier)
    fresh.each do |path, bytes|
      rel = path.delete_prefix("#{ROOT}/")
      next problems << "missing golden #{rel}" unless File.exist?(path)

      committed = File.binread(path).force_encoding(bytes.encoding)
      problems << "golden differs #{rel}#{first_difference(committed, bytes)}" unless committed == bytes
    end
    problems.concat(stale(tier, fresh.keys))
  end

  def stale(tier, expected)
    Dir.glob(File.join(golden_dir(tier), "**", "*.{json,ttf}")).reject { |p| expected.include?(p) }
      .map { |p| "stale golden #{p.delete_prefix("#{ROOT}/")} (no manifest font)" }
  end

  def first_difference(committed, fresh)
    return " (binary, #{committed.bytesize} vs #{fresh.bytesize} bytes)" unless fresh.encoding == Encoding::UTF_8

    a = committed.force_encoding("UTF-8").lines
    b = fresh.lines
    n = a.zip(b).index { |x, y| x != y }
    n ? " at line #{n + 1}: committed #{a[n]&.strip.inspect} fresh #{b[n]&.strip.inspect}" : ""
  end
end

if $PROGRAM_NAME == __FILE__
  tier = ARGV.fetch(0, "ci")
  puts "wrote #{CorpusGoldens.write(tier)} goldens (tier #{tier})"
end
