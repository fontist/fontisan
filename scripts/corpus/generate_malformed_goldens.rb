# frozen_string_literal: true

# Malformed-input goldens (fontist/fontisan#156, card 0e).
#
# For each committed malformed font (manifest entries with "malformed_kind")
# this records what the Ruby reference does on each operation: outcome, error
# class, normalised message (paths and numbers masked), position/context
# markers and the point where it fails. Read-type operations go through
# Fontisan::Reference; the per-step probe (load, name, table reads) uses
# FontLoader directly because the facade has no per-step operation.
#
#   ruby scripts/corpus/generate_malformed_goldens.rb [--check]
#
# Writes corpus/goldens/malformed/<id>.json. --check compares instead of writing
# (used by rake corpus:malformed:verify).
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "fontisan"
require "digest"
require "fileutils"
require "json"

module MalformedGoldens
  ROOT = File.expand_path("../..", __dir__)
  MANIFEST = File.join(ROOT, "corpus", "manifest.json")
  DERIVED_DIR = File.join(ROOT, "corpus", "derived")
  GOLDEN_DIR = File.join(ROOT, "corpus", "goldens", "malformed")

  COMBOS = [[:metadata, true], [:metadata, false],
            [:full, true], [:full, false]].freeze

  # Steps tried in order after a load; the first failing one is the failure
  # point. table_cmap is full-mode only (metadata gates it out by design).
  STEPS = %w[load name table_head table_cmap].freeze

  PATH_RE = %r{(?<![\w/])(?:[A-Za-z]:)?(?:\.{0,2}/)(?:[\w.~+-]+/)*[\w.~+-]*|
               (?:[\w.~+-]+/)*[\w.~+-]+\.(?:ttf|otf|ttc|otc|woff2?|dfont|pf[ab]|json|rb)\b}x
  HEX_RE = /0x\h+/i
  NUM_RE = /\d+/

  MARKER_RES = [
    /end of file reached/i,
    /\boffset\s*[:=]?\s*\d+/i,
    /\bposition\s*[:=]?\s*\d+/i,
    /\bbyte\s+\d+/i,
    /\bglyph\s+\d+/i,
    /\bindex\s+\d+/i,
    /\btable\s+['"][^'"]{1,4}['"]/i,
  ].freeze

  module_function

  def entries
    JSON.parse(File.read(MANIFEST)).fetch("fonts")
      .select { |e| e["malformed_kind"] }.sort_by { |e| e["id"] }
  end

  # Mask paths first (they contain digits), then hex, then decimal numbers.
  def normalize_message(message)
    message.to_s.gsub(PATH_RE, "<PATH>").gsub(HEX_RE, "<HEX>").gsub(NUM_RE, "<N>")
  end

  def markers(*messages)
    messages.compact.flat_map do |m|
      MARKER_RES.flat_map { |re| m.scan(re).map { |s| normalize_message(s.downcase) } }
    end.uniq.sort
  end

  def causes(exception)
    out = []
    cause = exception.cause
    while cause && out.size < 5
      out << { class: cause.class.name, message: normalize_message(cause.message) }
      cause = cause.cause
    end
    out
  end

  def error_record(exception)
    {
      outcome: "error",
      error_class: exception.class.name,
      message: normalize_message(exception.message),
      markers: markers(exception.message, *causes(exception).map { |c| c[:message] }),
      causes: causes(exception),
    }
  end

  def attempt
    { outcome: "ok" }.merge(yield || {})
  rescue StandardError => e
    error_record(e)
  end

  def digest(data)
    Digest::SHA256.hexdigest(Fontisan::Reference.canonical_json(data))
  end

  def probe_step(step, path, mode, lazy, font)
    case step
    when "load"
      attempt { { format: Fontisan::FontLoader.detect_format(path).to_s } }
    when "name"
      attempt { { family: font.table("name").english_name(1) } }
    when "table_head"
      attempt { { units_per_em: font.table("head").units_per_em } }
    when "table_cmap"
      attempt { { mappings: font.table("cmap").unicode_mappings.size } }
    end
  end

  # load, name, table reads, read: per (mode, lazy).
  def combo(path, mode, lazy)
    steps = {}
    font = nil
    steps["load"] = attempt do
      font = Fontisan::FontLoader.load(path, mode: mode, lazy: lazy)
      { format: font.class.name }
    end
    (STEPS - ["load"]).each do |step|
      next if step == "table_cmap" && mode == :metadata

      steps[step] = if font
                      probe_step(step, path, mode, lazy, font)
                    else
                      { outcome: "skipped", reason: "load failed" }
                    end
    end
    font.close if font.respond_to?(:close)
    steps["read"] = attempt do
      faces = Fontisan::Reference.read(path, mode: mode, lazy: lazy)
      { faces: faces.size, digest: digest(faces) }
    end
    failing = STEPS.find { |s| steps[s] && steps[s][:outcome] == "error" }
    { failure_point: failing, ops: steps }
  end

  def audit(path)
    attempt do
      reports = Fontisan::Reference.audit(path)
      { faces: reports.size, digest: digest(reports) }
    end
  end

  def scan(path)
    rows = Fontisan::Reference.scan([path])
    rows.each { |r| r["path"] = File.basename(r["path"]) }
    {
      outcome: "ok",
      rows: rows.size,
      digest: digest(rows),
      summary: rows.map { |r| scan_summary(r) },
    }
  rescue StandardError => e
    error_record(e)
  end

  def scan_summary(row)
    errors = row["errors"].transform_values do |err|
      next nil unless err

      { class: err["class"], message: normalize_message(err["message"]),
        markers: markers(err["message"]),
        cause: err["cause"] && { class: err["cause"]["class"],
                                 message: normalize_message(err["cause"]["message"]) } }
    end
    { format: row["format"], num_faces: row["num_faces"],
      validation_status: row["validation"] && row["validation"]["status"],
      errors: errors }
  end

  def golden(entry, dir: DERIVED_DIR)
    path = File.join(dir, entry.fetch("file"))
    {
      id: entry["id"], kind: entry["malformed_kind"], file: entry["file"],
      file_sha256: Digest::SHA256.file(path).hexdigest,
      comparison: "exact",
      combos: COMBOS.to_h { |m, l| ["#{m}/lazy=#{l}", combo(path, m, l)] },
      audit: audit(path),
      scan: scan(path)
    }
  end

  def render(entry, dir: DERIVED_DIR)
    Fontisan::Reference.canonical_json(golden(entry, dir: dir))
  end

  def golden_path(entry)
    File.join(GOLDEN_DIR, "#{entry['id']}.json")
  end

  # @return [Array<String>] problems; empty when the committed goldens match
  def verify(dir: DERIVED_DIR)
    problems = []
    entries.each do |e|
      gp = golden_path(e)
      unless File.exist?(gp)
        problems << "#{e['id']}: golden missing"
        next
      end
      actual = render(e, dir: dir)
      problems << "#{e['id']}: golden differs from current behaviour" unless File.read(gp) == actual
    end
    extra = Dir[File.join(GOLDEN_DIR, "*.json")].map { |f| File.basename(f, ".json") } - entries.map { |e| e["id"] }
    problems.concat(extra.map { |x| "#{x}: golden has no manifest entry" })
    problems
  end

  def regenerate
    FileUtils.mkdir_p(GOLDEN_DIR)
    entries.each { |e| File.write(golden_path(e), render(e)) }
    entries.size
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.include?("--check")
    problems = MalformedGoldens.verify
    abort problems.join("\n") unless problems.empty?
    puts "malformed goldens ok (#{MalformedGoldens.entries.size})"
  else
    puts "wrote #{MalformedGoldens.regenerate} malformed goldens"
  end
end
