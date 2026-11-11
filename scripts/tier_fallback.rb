# frozen_string_literal: true

# Tier fallback checks with strict mode OFF (fontist/fontisan#156 card 3a).
#
#   ruby scripts/tier_fallback.rb TIERS [CORPUS_ROOT [SCENARIO]]
#
# TIERS is the comma list of non-Ruby tiers this platform is expected to have
# (native,ffi | ffi | none). Without SCENARIO it runs every scenario below, each
# in a fresh child process (a tier cannot be un-loaded), against the ci-tier
# corpus with FONTISAN_ENGINE_STRICT unset:
#
#   no_native, no_ffi            the forced tier removed -> every row served by
#                                ruby, rows equal the scan goldens
#   native_missing_symbol,       the extension / library lacks a symbol, or speaks
#   native_abi_mismatch,         another ABI: the tier probes unavailable, nothing
#   ffi_missing_symbol,          raises (no NameError) and ruby serves golden rows
#   ffi_abi_mismatch
#   mixed                        dfont and Type 1 rows are served by ruby, the
#                                rest by the forced tier
#   auto_all, auto_no_native,    `auto` resolves to the first Engine::AUTO_ORDER tier
#   auto_none                    still present (ruby until the #160 gates flip it)
#
# A scenario about a tier the platform lacks is skipped. Run it against an
# INSTALLED gem on the CI matrix (outside the checkout), or locally with
# `bundle exec ruby scripts/tier_fallback.rb ...` from a checkout.
# Exit status 0 only when every scenario holds.
require "json"
require "rbconfig"
require "tmpdir"
require "fileutils"

SCENARIOS = %w[no_native no_ffi native_missing_symbol native_abi_mismatch
               ffi_missing_symbol ffi_abi_mismatch mixed
               auto_all auto_no_native auto_none].freeze

usage = "usage: tier_fallback.rb native,ffi|ffi|none [corpus root [scenario]]"
tiers = ARGV.fetch(0) { abort usage }.split(",") - ["none"]
root = File.expand_path(ARGV.fetch(1, File.join(__dir__, "..", "corpus")))
scenario = ARGV[2]
abort "unknown tiers #{tiers.inspect}" unless (tiers - %w[native ffi]).empty?

unless scenario
  results = SCENARIOS.to_h do |name|
    [name, system(RbConfig.ruby, __FILE__, tiers.join(",").then { |t| t.empty? ? "none" : t }, root, name)]
  end
  failed = results.reject { |_, ok| ok }.keys
  puts failed.empty? ? "all #{SCENARIOS.size} fallback scenarios hold" : "FAILED: #{failed.join(', ')}"
  exit(failed.empty? ? 0 : 1)
end

abort "unknown scenario #{scenario.inspect}" unless SCENARIOS.include?(scenario)

# --- sabotage that must happen before the gem loads -----------------------

module Sabotage
  # Takes the native extension away through the probe's own require.
  module BlockNative
    def require(name)
      raise LoadError, "native extension removed for the test" if name.to_s.include?("fontisan_native")

      super
    end
  end

  # A library lacking the fontisan_call symbol.
  module MissingFfiSymbol
    def attach_function(name, *rest)
      raise FFI::NotFoundError.new(name.to_s, "library") if name == :fontisan_call

      super
    end
  end
end

ENV["FONTISAN_ENGINE"] = "auto"
ENV.delete("FONTISAN_ENGINE_STRICT")
case scenario
when "no_native", "auto_no_native", "auto_none" then Object.prepend(Sabotage::BlockNative)
end
case scenario
when "no_ffi", "auto_none" then ENV["FONTISAN_CDYLIB"] = File.join(Dir.tmpdir, "fontisan-no-such-dir", "libfontisan_cdylib.none")
end
require "ffi" if scenario == "ffi_missing_symbol" && tiers.include?("ffi")
FFI::Library.prepend(Sabotage::MissingFfiSymbol) if defined?(FFI::Library) && scenario == "ffi_missing_symbol"
require "fontisan"
Fontisan::Reference # autoloading it installs the engine gates

needs = { "no_native" => "native", "native_missing_symbol" => "native", "native_abi_mismatch" => "native",
          "no_ffi" => "ffi", "ffi_missing_symbol" => "ffi", "ffi_abi_mismatch" => "ffi",
          "auto_no_native" => "native" }[scenario]
if needs && !tiers.include?(needs)
  puts "skip #{scenario}: no #{needs} tier on this platform"
  exit 0
end

case scenario
when "native_missing_symbol"
  Fontisan::Native.send(:load_extension)
  Fontisan::Native.singleton_class.send(:undef_method, :extension_abi_version)
when "native_abi_mismatch"
  Fontisan::Native.send(:remove_const, :ABI_VERSION)
  Fontisan::Native.const_set(:ABI_VERSION, 999)
when "ffi_abi_mismatch"
  require "fontisan/ffi/client"
  Fontisan::Ffi::Client.send(:remove_const, :ABI_VERSION)
  Fontisan::Ffi::Client.const_set(:ABI_VERSION, 999)
end

# --- checks ---------------------------------------------------------------

HANDED_TO_RUBY = %w[.dfont .pfa .pfb].freeze
manifest = JSON.parse(File.read(File.join(root, "manifest.json"))).fetch("fonts")
entries = manifest.select { |f| f["tier"] == "ci" }.sort_by { |f| f["id"] }
problems = []

font_path = lambda do |entry|
  File.join(root, entry["type"] == "derived" ? "derived" : File.join("fonts", entry["id"]), entry["file"])
end
golden = lambda do |entry|
  JSON.parse(File.read(File.join(root, "goldens", "scan", "#{entry['id']}.json"))).fetch("rows")
end
plain = lambda do |rows|
  JSON.parse(JSON.generate(rows.map { |r| r.except("served_by").merge("path" => File.basename(r["path"])) }))
end

# Scan every font; rows equal the goldens, served_by is in allowed.(path).
scan_corpus = lambda do |allowed|
  served = Hash.new(0)
  entries.each do |entry|
    path = font_path.call(entry)
    # The java gem has no brotli: with the ffi tier sabotaged nothing can read a WOFF2,
    # and the engine says so instead of falling back to a Ruby that cannot serve it.
    if File.extname(path).casecmp?(".woff2") && allowed.call(path) == ["ruby"] && !Fontisan::Utilities::BrotliWrapper.available?
      begin
        Fontisan::Engine.scan([path])
        problems << "#{entry['id']}: WOFF2 scan with no ffi tier and no brotli did not raise Woff2Unavailable"
      rescue Fontisan::Engine::Woff2Unavailable
        served["unavailable"] += 1
      end
      next
    end
    rows = Fontisan::Engine.scan([path])
    problems << "#{entry['id']}: rows differ from the golden" unless plain.call(rows) == golden.call(entry)
    rows.each do |row|
      served[row["served_by"]] += 1
      want = allowed.call(path)
      problems << "#{entry['id']}: served_by #{row['served_by']}, expected #{want.join('|')}" unless want.include?(row["served_by"])
    end
  end
  served
end
resolved = lambda do
  Fontisan::Engine.resolve(:scan, font_path.call(entries.find { |e| e["id"] == "fonttools-test-ttf" })).to_s
end
all_ruby = ->(_path) { ["ruby"] }

# The scenarios that sabotage nothing first check the platform has the tiers it claims.
if %w[mixed auto_all].include?(scenario)
  ENV["FONTISAN_ENGINE"] = "auto"
  Fontisan::Engine.reset!
  have = %w[native ffi].select { |t| Fontisan::Engine.send(:available?, t.to_sym) }
  problems << "available tiers are #{have.inspect}, expected #{tiers.inspect}" unless have == tiers
end

begin
  case scenario
  when "no_native", "no_ffi", "native_missing_symbol", "native_abi_mismatch", "ffi_missing_symbol", "ffi_abi_mismatch"
    tier = scenario[/native|ffi/]
    ENV["FONTISAN_ENGINE"] = tier
    Fontisan::Engine.reset!
    problems << "#{tier} probes available" if Fontisan::Engine.send(:available?, tier.to_sym)
    served = scan_corpus.call(all_ruby)
    problems << "no ruby row served" if served["ruby"].zero?
  when "mixed"
    tiers.each do |tier|
      ENV["FONTISAN_ENGINE"] = tier
      Fontisan::Engine.reset!
      # dfont and PFB must be ruby's. Ruby's detect_format does not recognise a
      # PFA (nil), so the tier may take it; its error row equals the golden either way.
      # Anything detect_format cannot name (empty or garbage bytes) is Ruby's too.
      scan_corpus.call(lambda { |path|
        case File.extname(path).downcase
        when ".dfont", ".pfb" then ["ruby"]
        when ".pfa" then ["ruby", tier]
        else Fontisan::FontLoader.detect_format(path).nil? ? ["ruby"] : [tier]
        end
      })
    end
    # dfont and Type 1 in one audit_dir: ruby serves those entries, the tier the rest.
    Dir.mktmpdir("fontisan-mixed") do |dir|
      %w[fonttools-test-ttf fonttools-test-dfont fonttools-test-t1-pfb].each do |id|
        entry = entries.find { |e| e["id"] == id }
        FileUtils.cp(font_path.call(entry), dir)
      end
      tiers.each do |tier|
        ENV["FONTISAN_ENGINE"] = tier
        Fontisan::Engine.reset!
        by_file = Fontisan::Engine.audit_dir(dir).to_h { |e| [e["path"], e["served_by"]] }
        want = { "TestTTF.ttf" => tier, "TestDFONT.dfont" => "ruby", "TestT1-Regular.pfb" => "ruby" }
        problems << "#{tier} audit_dir served #{by_file.inspect}, expected #{want.inspect}" unless by_file == want
      end
    end
    problems << "mixed scenario needs a native or ffi tier" if tiers.empty?
  when "auto_all", "auto_no_native", "auto_none"
    ENV["FONTISAN_ENGINE"] = "auto"
    Fontisan::Engine.reset!
    present = { "auto_all" => tiers, "auto_no_native" => tiers - ["native"], "auto_none" => [] }.fetch(scenario)
    want = Fontisan::Engine::AUTO_ORDER.map(&:to_s).find { |t| t == "ruby" || present.include?(t) }
    problems << "auto resolved #{resolved.call}, expected #{want}" unless resolved.call == want
    served = scan_corpus.call(->(path) { [want, *("ruby" if HANDED_TO_RUBY.include?(File.extname(path).downcase))] })
    problems << "no #{want} row served" if served[want].zero?
  end
rescue StandardError => e # NameError included: a fallback must never raise it
  problems << "raised #{e.class}: #{e.message[0, 200]}"
end

puts "#{problems.empty? ? 'ok  ' : 'FAIL'} #{scenario} (tiers: #{tiers.join(',')})"
problems.each { |p| puts "       #{p}" }
exit(problems.empty? ? 0 : 1)
