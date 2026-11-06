# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "zlib"
require "fontisan"
require_relative "../../corpus/derive/sfnt"

# Convert goldens (fontist/fontisan#156, card 0c).
#
# One golden file per corpus font: corpus/goldens/convert/<font-id>.json. Each
# holds one result per applicable case, generated through Fontisan::Reference:
#
#   format:<to>        Reference.convert (single fonts: ttf otf woff woff2;
#                      collections: ttc otc woff2), every target but the source
#   extract:<i>        Reference.extract, every collection member
#   instance:<i>       Reference.instance, every named instance of an fvar font
#   subset:text-latin / subset:unicodes-sample   Reference.subset, profile "web"
#
# A result records the comparison class (index rule): "exact" (sha256 of the
# raw output bytes) except WOFF/WOFF2 encode, "decoded-exact" (the output
# sha256 plus the per-table sha256 after decoding), and the OTS verdict.
# Nothing is stored but hashes. Errors are goldens too (class + masked message).
module ConvertGoldens
  ROOT = File.expand_path("../..", __dir__)
  GOLDEN_DIR = File.join(ROOT, "corpus", "goldens", "convert")
  MANIFEST = File.join(ROOT, "corpus", "manifest.json")
  TRIAGE = File.join(ROOT, "corpus", "TRIAGE_CONVERT.md")
  # The one fixed head.modified for WOFF2 encode (2025-01-01T00:00:00Z).
  TIMESTAMP = 1_735_689_600
  SINGLE_TARGETS = %w[ttf otf woff woff2].freeze
  COLLECTION_TARGETS = %w[ttc otc woff2].freeze
  SUBSET_TEXT = "Hamburgefonstiv 0123"
  SUBSET_SAMPLE = 8
  MAGICS = {
    "\x00\x01\x00\x00".b => "ttf", "true" => "ttf", "OTTO" => "otf",
    "wOFF" => "woff", "wOF2" => "woff2", "ttcf" => "ttc"
  }.freeze
  # Not convert subjects: malformed inputs are card 0e's, dfont/Type 1 are
  # routing-only rows.
  EXCLUDED_ID = /\Amalformed-/
  OUTPUT_EXT = { "ttf" => "ttf", "otf" => "otf", "woff" => "woff", "woff2" => "woff2",
                 "ttc" => "ttc", "otc" => "otc" }.freeze

  class ToolMissing < StandardError; end

  module_function

  def manifest_entries(tiers)
    JSON.parse(File.read(MANIFEST)).fetch("fonts").select { |f| tiers.include?(f["tier"]) }
  end

  def font_path(entry)
    if entry["type"] == "derived"
      File.join(ROOT, "corpus", "derived", entry.fetch("file"))
    else
      File.join(ROOT, "corpus", "fonts", entry.fetch("id"), entry.fetch("file"))
    end
  end

  def sniff(path)
    MAGICS[File.binread(path, 4)]
  end

  # Fonts that are convert subjects, with their detected input format.
  def subjects(tiers)
    manifest_entries(tiers).filter_map do |entry|
      next if entry["id"].match?(EXCLUDED_ID)

      path = font_path(entry)
      next unless File.exist?(path)

      format = sniff(path)
      format ? [entry, path, format] : nil
    end
  end

  # --- case enumeration ---------------------------------------------------

  def read_faces(path)
    Fontisan::Reference.read(path, mode: :full, lazy: false)
  end

  def instance_coords(face)
    fvar = face["fvar"] or return []
    tags = fvar["axes"].map { |a| a["axis_tag"] }
    fvar["instances"].map do |inst|
      tags.zip(inst["coordinates_raw"]).to_h { |tag, raw| [tag, raw.to_f / Fontisan::Reference::FIXED_ONE] }
    end
  end

  # => { "format:ttf" => {op: :format, to: "ttf"}, ... } in a fixed order
  def cases_for(path, format)
    faces = read_faces(path)
    cases = {}
    if format == "ttc" || faces.size > 1 || collection?(path)
      COLLECTION_TARGETS.each { |to| cases["format:#{to}"] = { op: :format, to: to } }
      faces.each_index { |i| cases["extract:#{i}"] = { op: :extract, index: i } }
      return cases
    end
    SINGLE_TARGETS.each { |to| cases["format:#{to}"] = { op: :format, to: to } unless to == format }
    instance_coords(faces.first).each_with_index do |coords, i|
      cases["instance:#{i}"] = { op: :instance, coords: coords }
    end
    cases["subset:text-latin"] = { op: :subset, text: SUBSET_TEXT }
    cases["subset:unicodes-sample"] = { op: :subset, sample: true }
    cases
  end

  def collection?(path)
    File.binread(path, 4) == "ttcf" || (File.binread(path, 4) == "wOF2" && woff2_flavor(path) == "ttcf")
  end

  def woff2_flavor(path)
    File.binread(path, 8).byteslice(4, 4)
  end

  def sample_codepoints(path)
    cps = cmap_codepoints(path)
    return cps if cps.size <= SUBSET_SAMPLE

    step = (cps.size - 1).fdiv(SUBSET_SAMPLE - 1)
    Array.new(SUBSET_SAMPLE) { |i| cps[(i * step).round] }.uniq
  end

  # Codepoints of a face's cmap. A WOFF2 input on a platform without the `brotli`
  # gem (the java gem on JRuby) is decoded by the pinned woff2_decompress first,
  # so the sample does not depend on the tier under test.
  def cmap_codepoints(path)
    return load_codepoints(path) unless File.binread(path, 4) == "wOF2" && !Fontisan::Utilities::BrotliWrapper.available?

    Dir.mktmpdir("sample-cps") do |tmp|
      input = File.join(tmp, "in.woff2")
      FileUtils.cp(path, input)
      _out, err, status = Open3.capture3(woff2_decompress, input)
      decoded = File.join(tmp, "in.ttf")
      raise "woff2_decompress failed: #{err.strip}" unless status.success? && File.exist?(decoded)

      load_codepoints(decoded)
    end
  end

  def load_codepoints(path)
    Fontisan::FontLoader.load(path, mode: :full, lazy: false).table("cmap").unicode_mappings.keys.sort
  end

  # --- tools ----------------------------------------------------------------

  def ots_command
    @ots_command ||= (ENV["OTS_PYTHON"] || "python3").then { |py| [py, "-m", "ots"] }
  end

  def woff2_decompress
    @woff2_decompress ||= ENV["WOFF2_DECOMPRESS"] ||
      Open3.capture2(File.join(ROOT, "scripts", "build-woff2.sh"), err: File::NULL).first.lines.last.to_s.strip
  end

  def check_tools!
    out, status = Open3.capture2e(*ots_command, "--version")
    ok = status.success? || out.include?("Usage") || out.include?("Unrecognized")
    raise ToolMissing, "OTS not runnable via `#{ots_command.join(' ')}` (set OTS_PYTHON): #{out.strip}" unless ok
    raise ToolMissing, "woff2_decompress not available" unless File.executable?(woff2_decompress.to_s)
  end

  # --- decoding -------------------------------------------------------------

  def table_digests_of_sfnt(bytes)
    if bytes.byteslice(0, 4) == "ttcf"
      CorpusSfnt.parse_ttc(bytes).map { |_v, tables| digest_tables(tables.to_h) }
    else
      [digest_tables(CorpusSfnt.parse(bytes).last.to_h)]
    end
  end

  def digest_tables(tables)
    tables.sort.to_h { |tag, data| [tag, Digest::SHA256.hexdigest(data)] }
  end

  def decode_woff(bytes)
    num = bytes.byteslice(12, 2).unpack1("n")
    tables = {}
    num.times do |i|
      tag, offset, comp, orig = bytes.byteslice(44 + (i * 20), 20).unpack("a4NNN")
      data = bytes.byteslice(offset, comp)
      tables[tag] = comp < orig ? Zlib::Inflate.inflate(data) : data
    end
    [digest_tables(tables)]
  end

  def decode_woff2(bytes, tmp)
    input = File.join(tmp, "decode.woff2")
    File.binwrite(input, bytes)
    _out, err, status = Open3.capture3(woff2_decompress, input)
    out = File.join(tmp, "decode.ttf")
    raise "woff2_decompress failed: #{err.strip}" unless status.success? && File.exist?(out)

    decoded = File.binread(out)
    FileUtils.rm_f([input, out])
    table_digests_of_sfnt(decoded)
  end

  def decoded_digests(format, bytes, tmp)
    case format
    when "woff" then decode_woff(bytes)
    when "woff2" then decode_woff2(bytes, tmp)
    end
  end

  # --- OTS ------------------------------------------------------------------

  def ots_run(path, index = nil)
    dest = File.join(File.dirname(path), "ots-dest.bin")
    args = [*ots_command, path]
    args.push(dest, index.to_s) if index
    out, status = Open3.capture2e(*args)
    FileUtils.rm_f(dest)
    status.success? ? nil : out.lines.grep(/ERROR|Failed/).first(2).map(&:strip).join(" | ")
  end

  # Collections are sanitised member by member; WOFF2 collections are first
  # decoded by the pinned woff2_decompress.
  def ots_verdict(path, format, tmp)
    target = path
    if format == "woff2" && woff2_flavor(path) == "ttcf"
      target = File.join(tmp, "ots-decoded.ttf")
      FileUtils.cp(path, File.join(tmp, "ots-decoded.woff2"))
      _o, _e, st = Open3.capture3(woff2_decompress, File.join(tmp, "ots-decoded.woff2"))
      return { "verdict" => "fail", "detail" => "woff2_decompress failed" } unless st.success?
    end
    failures = member_count(target).times.filter_map do |i|
      msg = ots_run(target, member_count(target) > 1 ? i : nil)
      "member #{i}: #{msg}" if msg
    end
    { "verdict" => failures.empty? ? "pass" : "fail" }.tap { |v| v["detail"] = failures.join(" ; ") unless failures.empty? }
  end

  # Index rule: a golden whose output fails OTS is a known_reference_bug; the
  # tag is the first OTS error with numbers masked.
  def ots_bug_tag(detail)
    first = detail.to_s[/ERROR: ([^|;]+)/, 1] || detail.to_s
    first.strip.gsub(/\b\d+\b/, "N")
  end

  def member_count(path)
    return 1 unless File.binread(path, 4) == "ttcf"

    File.binread(path, 12).unpack1("@8N")
  end

  # --- running a case -------------------------------------------------------

  def mask(message, tmp)
    message.to_s.gsub(tmp, "<tmp>").gsub(ROOT, "<root>").gsub(/0x\h+/, "0x?")
      .gsub(%r{(?:/[\w.\-\[\],]+)+/}, "<dir>/").gsub(/\b\d+\b/, "N").lines.first.to_s.strip
  end

  def run_case(path, format, spec, tmp)
    result = { "params" => params_of(spec) }
    result["class"] = spec[:op] == :format && %w[woff woff2].include?(spec[:to]) ? "decoded-exact" : "exact"
    out_path, out_format = produce(path, spec, tmp)
    bytes = File.binread(out_path)
    result["outcome"] = "ok"
    result["output"] = { "format" => out_format, "sha256" => Digest::SHA256.hexdigest(bytes), "size" => bytes.bytesize }
    result["output"]["basename"] = File.basename(out_path) if spec[:op] == :extract
    decoded = decoded_digests(out_format, bytes, tmp)
    result["decoded_tables"] = decoded if decoded
    result["ots"] = ots_verdict(out_path, out_format, tmp)
    result["known_reference_bug"] = ots_bug_tag(result["ots"]["detail"]) if result["ots"]["verdict"] == "fail"
    result
  rescue ToolMissing
    raise
  rescue StandardError => e
    result.merge("outcome" => "error", "error" => { "class" => e.class.name, "message" => mask(e.message, tmp) })
  ensure
    FileUtils.rm_rf(Dir.glob(File.join(tmp, "*")))
  end

  def params_of(spec)
    params = spec.except(:op, :coords).transform_keys(&:to_s).merge("op" => spec[:op].to_s)
    params["coords_raw"] = spec[:coords].transform_values { |v| (v * Fontisan::Reference::FIXED_ONE).round } if spec[:coords]
    params.sort.to_h
  end

  def produce(path, spec, tmp)
    case spec[:op]
    when :format
      out = File.join(tmp, "out.#{OUTPUT_EXT.fetch(spec[:to])}")
      Fontisan::Reference.convert(path, to: spec[:to], output: out, timestamp: TIMESTAMP)
      [out, sniff(out) || "unknown"]
    when :extract
      out = Fontisan::Reference.extract(path, index: spec[:index], output_dir: tmp)
      [out, sniff(out) || "unknown"]
    when :instance
      write_bytes(tmp, Fontisan::Reference.instance(path, coords: spec[:coords], timestamp: TIMESTAMP))
    when :subset
      write_bytes(tmp, Fontisan::Reference.subset(path, **subset_args(path, spec), profile: "web", timestamp: TIMESTAMP))
    end
  end

  def write_bytes(tmp, bytes)
    out = File.join(tmp, "out.bin")
    File.binwrite(out, bytes)
    [out, sniff(out) || "unknown"]
  end

  def subset_args(path, spec)
    spec[:text] ? { text: spec[:text] } : { unicodes: sample_codepoints(path) }
  end

  # --- golden assembly ------------------------------------------------------

  def golden_for(entry, path, format)
    specs = cases_for(path, format)
    results = {}
    Dir.mktmpdir("convert-golden") do |tmp|
      specs.each do |key, spec|
        results[key] = run_case(path, format, spec, tmp)
        results[key]["params"]["unicodes"] = sample_codepoints(path) if spec[:sample]
        results[key]["params"].delete("sample")
      end
    end
    { "font" => entry["id"], "source_sha256" => Digest::SHA256.file(path).hexdigest,
      "source_format" => format, "timestamp" => TIMESTAMP, "cases" => results }
  end

  # Returns { "<font-id>.json" => canonical json text }.
  def generate(tiers, only: nil)
    check_tools!
    subjects(tiers).each_with_object({}) do |(entry, path, format), files|
      next if only && !Array(only).include?(entry["id"])

      files["#{entry['id']}.json"] = Fontisan::Reference.canonical_json(golden_for(entry, path, format))
    end
  end

  def expected_keys(tiers)
    subjects(tiers).to_h { |entry, path, format| [entry["id"], cases_for(path, format).keys] }
  end

  REASONS = {
    /Variations: Required fvar/ => "static output drops fvar/gvar but GDEF/GPOS keep ItemVariationStore references (measured: instance and VF->static convert outputs)",
    /post: Bad number of glyphs/ => "subset leaves the post table at the source glyph count (not subsetted)",
    /CFF : Failed to parse Name INDEX/ => "TTF->OTF conversion writes a CFF table with an invalid Name INDEX",
    /Layout: bad glyph/ => "subset leaves GSUB/GPOS referencing glyph ids beyond the subset glyph count",
    /overlapping tables/ => "TTC writer emits overlapping table records for shared tables",
    /zero-length table|missing required table|invalid table offset|Unsupported majorVersion/ =>
      "input is a deliberate quirk font (corpus/derive/quirks.rb); Ruby passes the quirk through and OTS rejects it",
    /cmap: bad glyph id offset/ => "extracted member keeps a cmap invalid for OTS (TestTTCv2)",
    /glyf: Count too high/ => "WOFF encode of a WOFF2-decoded TTF writes a glyf table OTS rejects",
  }.freeze

  def reason_for(tag)
    REASONS.each { |re, why| return why if tag.match?(re) }
    "unclassified"
  end

  # corpus/TRIAGE_CONVERT.md: every OTS exception, grouped by failure tag.
  def triage_text(dir = GOLDEN_DIR)
    groups = Hash.new { |h, k| h[k] = [] }
    Dir.glob(File.join(dir, "*.json")).each do |file|
      g = JSON.parse(File.read(file))
      g["cases"].each { |k, v| groups[v["known_reference_bug"]] << "#{g['font']}/#{k}" if v.dig("ots", "verdict") == "fail" }
    end
    lines = ["# Convert goldens: OTS exceptions (card 0c)", "",
             "Generated by `rake corpus:convert:regenerate`; do not edit by hand. Each entry is a",
             "`known_reference_bug`: the golden keeps Ruby's output, Rust reproduces it, and the output",
             "fails OTS (`python -m ots`). Fixing the Ruby behaviour regenerates the golden and removes the entry.", ""]
    groups.sort_by { |tag, _| tag }.each do |tag, ids|
      lines << "## #{tag} (#{ids.size})" << "" << "Reason: #{reason_for(tag)}." << ""
      ids.sort.each { |id| lines << "- OTS exception: `#{id}`" }
      lines << ""
    end
    lines.concat(known_notes)
    lines.concat(error_section(dir))
    "#{lines.join("\n")}\n"
  end

  def known_notes
    ["# Known reference bugs outside OTS", "",
     "- `Tables::Cff::CharString` hintmask/cntrmask: `@io&.read` is nil for the top-level mask bytes, so they are",
     "  not skipped and CID-keyed CFF glyphs become empty (visible in noto-sans-jp-subset-regular-otf otf->ttf",
     "  and its subsets). known_reference_bug: goldens keep Ruby's output; Rust reproduces it.", ""]
  end

  # Cases where Ruby raises: recorded as error goldens (Rust must raise the
  # same class and message). Listed so a wrong-looking error is not mistaken
  # for a harness fault.
  def error_section(dir)
    errors = Hash.new { |h, k| h[k] = [] }
    Dir.glob(File.join(dir, "*.json")).each do |file|
      g = JSON.parse(File.read(file))
      g["cases"].each do |k, v|
        errors["#{v['error']['class']}: #{v['error']['message']}"] << "#{g['font']}/#{k}" if v["outcome"] == "error"
      end
    end
    out = ["# Reference errors (error goldens)", "",
           "Ruby raises on these inputs today; the golden keeps class and masked message.", ""]
    errors.sort.each do |msg, ids|
      out << "## #{msg} (#{ids.size})" << ""
      ids.sort.each { |id| out << "- Reference error: `#{id}`" }
      out << ""
    end
    out
  end

  def write(files, dir = GOLDEN_DIR)
    FileUtils.mkdir_p(dir)
    files.each { |name, text| File.write(File.join(dir, name), text) }
    File.write(TRIAGE, triage_text(dir)) if dir == GOLDEN_DIR
  end

  # => array of human-readable problems (empty = golden matches)
  def verify(tiers, only: nil, dir: GOLDEN_DIR)
    generated = generate(tiers, only: only)
    problems = []
    generated.each do |name, text|
      file = File.join(dir, name)
      if !File.exist?(file) then problems << "#{name}: golden missing"
      elsif !same_golden?(File.read(file), text) then problems << "#{name}: #{diff_cases(File.read(file), text)}"
      end
    end
    unless only
      stale = Dir.children(dir).grep(/\.json\z/) - generated.keys
      problems.concat(stale.map { |n| "#{n}: golden has no corpus font" })
    end
    problems
  end

  # Goldens are Ruby's output. A non-Ruby tier (FONTISAN_ENGINE=native|ffi|auto)
  # compresses with its own zlib/brotli, so for the "decoded-exact" class (woff,
  # woff2) its compressed size and sha256 may differ; the decoded tables must
  # not. Every other case is compared exactly, on every tier.
  def same_golden?(golden_text, new_text)
    return golden_text == new_text unless compressed_bytes_may_differ?

    relaxed(JSON.parse(golden_text)) == relaxed(JSON.parse(new_text))
  end

  def compressed_bytes_may_differ?
    !%w[ruby].include?(ENV.fetch("FONTISAN_ENGINE", "auto").strip.downcase)
  end

  def relaxed(golden)
    golden["cases"].each_value do |c|
      c["output"]&.delete_if { |k, _| %w[sha256 size].include?(k) } if c["class"] == "decoded-exact" && c["outcome"] == "ok"
    end
    golden
  end

  def diff_cases(old_text, new_text)
    old = JSON.parse(old_text)["cases"]
    new = JSON.parse(new_text)["cases"]
    keys = (old.keys | new.keys).reject { |k| old[k] == new[k] }
    keys.empty? ? "header differs" : "differs in #{keys.join(', ')}"
  end

  # OTS failures that the golden records, as "<font-id>/<case-key>".
  def ots_failures(dir = GOLDEN_DIR)
    Dir.glob(File.join(dir, "*.json")).flat_map do |file|
      g = JSON.parse(File.read(file))
      g["cases"].select { |_k, v| v.dig("ots", "verdict") == "fail" }.keys.map { |k| "#{g['font']}/#{k}" }
    end.sort
  end

  def listed_exceptions
    return [] unless File.exist?(TRIAGE)

    File.read(TRIAGE).scan(%r{^- OTS exception: `([^`]+)`}).flatten.sort
  end
end

if $PROGRAM_NAME == __FILE__
  tiers = ENV.fetch("TIERS", "ci").split(",")
  ConvertGoldens.write(ConvertGoldens.generate(tiers))
end
