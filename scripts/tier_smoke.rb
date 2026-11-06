# frozen_string_literal: true

# Installed-gem smoke test (fontist/fontisan#156 card 2e).
#
#   ruby scripts/tier_smoke.rb EXPECTED_TIER [CORPUS_ROOT]
#
# Run it against an INSTALLED fontisan gem (never the checkout's lib/). It scans
# every `ci`-tier corpus font through Fontisan::Engine under the default engine (FONTISAN_ENGINE unset = auto),
# then checks that
#   * the tier auto resolves to is EXPECTED_TIER (native, ffi or ruby);
#   * every row equals the committed scan golden (minus the served_by key);
#   * served_by is EXPECTED_TIER, except for files the engine hands to Ruby
#     (dfont, Type 1), which may say ruby; with EXPECTED_TIER=ruby nothing else.
# Exit status 0 only when all hold.
require "json"

expected = ARGV.fetch(0) { abort "usage: tier_smoke.rb native|ffi|ruby [corpus root]" }
root = File.expand_path(ARGV.fetch(1, File.join(__dir__, "..", "corpus")))
abort "unknown tier #{expected.inspect}" unless %w[native ffi ruby].include?(expected)

ENV.delete("FONTISAN_ENGINE") # the default (auto) is what is under test
ENV.delete("FONTISAN_ENGINE_STRICT")
require "fontisan"
Fontisan::Reference # autoloading it installs the engine gates

lib_dir = Gem.loaded_specs.fetch("fontisan").full_gem_path
abort "smoke must run an installed gem, loaded #{lib_dir}" unless File.basename(File.dirname(lib_dir)) == "gems"

HANDED_TO_RUBY = %w[.dfont .pfa .pfb].freeze

manifest = JSON.parse(File.read(File.join(root, "manifest.json"))).fetch("fonts")
entries = manifest.select { |f| f["tier"] == "ci" }.sort_by { |f| f["id"] }
problems = []
served = Hash.new(0)

entries.each do |entry|
  dir = entry["type"] == "derived" ? "derived" : File.join("fonts", entry["id"])
  path = File.join(root, dir, entry["file"])
  golden = JSON.parse(File.read(File.join(root, "goldens", "scan", "#{entry['id']}.json"))).fetch("rows")
  rows = Fontisan::Engine.scan([path])
  rows.each { |row| served[row["served_by"]] += 1 }

  actual = rows.map { |r| r.except("served_by").merge("path" => File.basename(r["path"])) }
  problems << "#{entry['id']}: rows differ from golden" unless JSON.parse(JSON.generate(actual)) == golden

  allowed = [expected]
  allowed << "ruby" if expected != "ruby" && HANDED_TO_RUBY.include?(File.extname(path).downcase)
  rows.each do |row|
    problems << "#{entry['id']}: served_by #{row['served_by']}, expected #{allowed.join('|')}" unless allowed.include?(row["served_by"])
  end
end

resolved = Fontisan::Engine.resolve(:scan, File.join(root, "fonts", "fonttools-test-ttf", "TestTTF.ttf")).to_s
problems << "auto resolves scan to #{resolved}, expected #{expected}" unless resolved == expected
problems << "no #{expected} row served" if served[expected].zero?

puts "fontisan #{Fontisan::VERSION} from #{lib_dir}"
puts "ruby #{RUBY_VERSION} #{RUBY_PLATFORM}; fonts scanned: #{entries.size}; served_by: #{served.inspect}"
if problems.empty?
  puts "OK: auto resolved to #{resolved}; rows equal the goldens"
else
  warn problems
  exit 1
end
