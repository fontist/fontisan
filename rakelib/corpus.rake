# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "tmpdir"
require "uri"

# Reference corpus (fontist/fontisan#157). The manifest is corpus/manifest.json:
#   source  - a font fetched from a pinned URL; sha256 is of the EXTRACTED font
#             (archives are not byte-stable, so the zip itself is never hashed)
#   derived - a small output committed under corpus/derived/, sha256 verified
module Corpus
  ROOT = File.expand_path("..", __dir__)
  MANIFEST = File.join(ROOT, "corpus", "manifest.json")
  FONTS_DIR = File.join(ROOT, "corpus", "fonts")
  DERIVED_DIR = File.join(ROOT, "corpus", "derived")
  MAX_REDIRECTS = 8
  ATTEMPTS = 3

  class Error < StandardError; end

  module_function

  def manifest
    JSON.parse(File.read(MANIFEST))
  end

  def tiers_for(selector)
    case selector.to_s
    when "", "ci" then %w[ci]
    when "large" then %w[large]
    when "all" then %w[ci large]
    else raise Error, "TIER must be ci, large or all (got #{selector.inspect})"
    end
  end

  def sha256(path)
    Digest::SHA256.file(path).hexdigest
  end

  def source_path(entry)
    File.join(FONTS_DIR, entry.fetch("id"), entry.fetch("file"))
  end

  def derived_path(entry)
    File.join(DERIVED_DIR, entry.fetch("file"))
  end

  def verify!(entry, path)
    raise Error, "#{entry['id']}: #{path} is missing" unless File.exist?(path)

    actual = sha256(path)
    return if actual == entry.fetch("sha256")

    raise Error, "#{entry['id']}: sha256 mismatch for #{File.basename(path)}\n  " \
                 "expected #{entry['sha256']}\n  actual   #{actual}"
  end

  # Streams url into dest, following redirects, retrying transient failures.
  def download(url, dest)
    attempt = 0
    begin
      attempt += 1
      stream(URI(url), dest, MAX_REDIRECTS)
    rescue StandardError => e
      FileUtils.rm_f(dest)
      raise Error, "download failed for #{url}: #{e.message}" if attempt >= ATTEMPTS

      warn "[corpus:fetch] retry #{attempt}/#{ATTEMPTS - 1} for #{url}: #{e.message}"
      sleep(attempt * 2)
      retry
    end
  end

  def stream(uri, dest, redirects)
    raise "too many redirects" if redirects.negative?

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                        read_timeout: 120) do |http|
      http.request_get(uri.request_uri, "User-Agent" => "fontisan-corpus") do |res|
        case res
        when Net::HTTPSuccess
          File.open(dest, "wb") { |f| res.read_body { |chunk| f.write(chunk) } }
        when Net::HTTPRedirection
          return stream(URI.join(uri.to_s, res["location"]), dest, redirects - 1)
        else
          raise "HTTP #{res.code}"
        end
      end
    end
  end

  def extract_member(zip_path, member, dest)
    require "zip"
    Zip::File.open(zip_path) do |zip|
      found = zip.find_entry(member) or raise Error, "#{member} not in archive"
      File.open(dest, "wb") { |out| IO.copy_stream(found.get_input_stream, out) }
    end
  end

  def fetch_source(entry)
    dest = source_path(entry)
    if File.exist?(dest) && sha256(dest) == entry["sha256"]
      puts "[corpus:fetch] ok      #{entry['id']}"
      return
    end

    FileUtils.mkdir_p(File.dirname(dest))
    Dir.mktmpdir("corpus-fetch") do |tmp|
      src = entry.fetch("source")
      if src["archive_member"]
        zip = File.join(tmp, "archive.zip")
        download(src.fetch("url"), zip)
        extracted = File.join(tmp, "member")
        extract_member(zip, src["archive_member"], extracted)
        FileUtils.mv(extracted, dest)
      else
        download(src.fetch("url"), dest)
      end
    end
    begin
      verify!(entry, dest)
    rescue Error
      FileUtils.rm_f(dest)
      raise
    end
    puts "[corpus:fetch] fetched #{entry['id']} (#{File.size(dest)} bytes)"
  end

  def entries(selector)
    tiers = tiers_for(selector)
    manifest.fetch("fonts").select { |f| tiers.include?(f["tier"]) }
  end

  def fetch(selector)
    list = entries(selector)
    list.select { |f| f["type"] == "source" }.each { |e| fetch_source(e) }
    list.select { |f| f["type"] == "derived" }.each do |e|
      verify!(e, derived_path(e))
      puts "[corpus:fetch] derived #{e['id']} verified"
    end
    sources = list.count { |f| f["type"] == "source" }
    puts "[corpus:fetch] #{sources} sources and #{list.size - sources} derived entries verified"
  end

  # --- WOFF2 cross-check with the pinned Google woff2_decompress ----------

  def woff2_decompress
    out, status = Open3.capture2(File.join(ROOT, "scripts", "build-woff2.sh"))
    raise Error, "scripts/build-woff2.sh failed" unless status.success?

    out.lines.last.strip
  end

  def path_for(entry)
    entry["type"] == "derived" ? derived_path(entry) : source_path(entry)
  end

  def tables_of(bytes)
    require_relative "../corpus/derive/sfnt"
    if bytes.byteslice(0, 4) == "ttcf"
      CorpusSfnt.parse_ttc(bytes).map { |_v, t| t.to_h }
    else
      [CorpusSfnt.parse(bytes).last.to_h]
    end
  end

  # WOFF2 drops DSIG, re-serialises glyf/loca (padding) and sets head
  # flags bit 11, checkSumAdjustment and modified. Everything else must be
  # byte-equal after decoding by the pinned Google decoder.
  HEAD_VOLATILE = [8..11, 16..16, 28..35].flat_map(&:to_a).freeze

  def glyph_slices(tables)
    loca_fmt = tables["head"].byteslice(50, 2).unpack1("n")
    offs = if loca_fmt.zero?
             tables["loca"].unpack("n*").map { |o| o * 2 }
           else
             tables["loca"].unpack("N*")
           end
    offs.each_cons(2).map { |a, b| tables["glyf"].byteslice(a, b - a).sub(/\0+\z/n, "") }
  end

  def compare_decoded(id, want, got)
    problems = []
    unless want.size == got.size
      return ["#{id}: #{got.size} members decoded, expected #{want.size}"]
    end

    want.zip(got).each_with_index do |(w, g), i|
      where = "#{id} member #{i}"
      expected_tags = w.keys - ["DSIG"]
      problems << "#{where}: table tags differ" unless expected_tags.sort == g.keys.sort
      (expected_tags & g.keys).each do |tag|
        case tag
        when "glyf", "loca" then next
        when "head"
          diff = (0...w[tag].bytesize).reject { |j| w[tag].getbyte(j) == g[tag].getbyte(j) }
          problems << "#{where}: head differs outside volatile fields: #{diff}" unless (diff - HEAD_VOLATILE).empty?
        else
          problems << "#{where}: table #{tag} differs after decode" unless w[tag] == g[tag]
        end
      end
      if w["glyf"] && g["glyf"] && glyph_slices(w) != glyph_slices(g)
        problems << "#{where}: glyph outlines differ after decode"
      end
    end
    problems
  end

  def check_woff2(selector)
    exe = woff2_decompress
    all = manifest.fetch("fonts")
    failures = []
    entries(selector).select { |e| e["woff2_decode"] }.each do |entry|
      Dir.mktmpdir("corpus-woff2") do |tmp|
        input = File.join(tmp, "in.woff2")
        FileUtils.cp(path_for(entry), input)
        _out, err, status = Open3.capture3(exe, input)
        # woff2_decompress writes <stem>.ttf even for collections: detect the
        # format by magic bytes, never by extension.
        out_path = File.join(tmp, "in.ttf")
        unless status.success? && File.exist?(out_path)
          failures << "#{entry['id']}: woff2_decompress failed: #{err.strip}"
          next
        end
        decoded = File.binread(out_path)
        magic = decoded.byteslice(0, 4)
        unless ["\x00\x01\x00\x00".b, "OTTO", "true", "ttcf"].include?(magic)
          failures << "#{entry['id']}: decoded output has magic #{magic.inspect}"
          next
        end
        if (ref_id = entry["woff2_decoded_equals"])
          ref = all.find { |f| f["id"] == ref_id }
          want = tables_of(File.binread(path_for(ref)))
          got = tables_of(decoded)
          problems = compare_decoded(entry["id"], want, got)
          failures.concat(problems)
          next unless problems.empty?
        end
        puts "[corpus:check_woff2] ok #{entry['id']} (#{magic == 'ttcf' ? 'collection' : 'single font'})"
      end
    end
    raise Error, "WOFF2 cross-check failed:\n  #{failures.join("\n  ")}" unless failures.empty?
  end
end

namespace :corpus do
  desc "Download and verify the corpus (TIER=ci|large|all, default ci)"
  task :fetch do
    Corpus.fetch(ENV.fetch("TIER", "ci"))
  rescue Corpus::Error => e
    abort "[corpus:fetch] #{e.message}"
  end

  desc "Cross-check WOFF2 entries with the pinned Google woff2_decompress"
  task check_woff2: :fetch do
    Corpus.check_woff2(ENV.fetch("TIER", "ci"))
  rescue Corpus::Error => e
    abort "[corpus:check_woff2] #{e.message}"
  end

  desc "Regenerate corpus/derived from corpus/derive scripts (provenance; run after fetch)"
  task derive: :fetch do
    ruby = %w[quirks malformed fuzz ttc_multi woff2_collection]
    ruby.each do |name|
      sh "bundle", "exec", "ruby", File.join(Corpus::ROOT, "corpus", "derive", "#{name}.rb")
    end
  end
end
