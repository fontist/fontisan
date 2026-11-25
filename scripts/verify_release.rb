# frozen_string_literal: true

# Post-release content assertions (operational rule: the shipped artifact must
# CONTAIN its expected elements — install the published gem and prove the new
# engine capabilities serve through the engine tier, not the Ruby tier).
#
# Usage: gem install fontisan -v 0.4.51 --no-document (in a scratch dir), then
#   FONTISAN_PROBE_VERSION=0.4.51 ruby scripts/verify_release.rb
# (with GEM_PATH pointed at the scratch install — the SHIPPED lib must load,
# never the checkout's lib/)
require "fontisan"
require "tmpdir"
require "fileutils"

version = ENV.fetch("FONTISAN_PROBE_VERSION")
spec = Gem::Specification.find_by_name("fontisan", version)
puts "installed gem: #{spec.full_gem_path}"

failures = []
fonts = File.expand_path("../../fontisan-rs/.corpus/fontisan/corpus/fonts", __dir__)

# 1. Platform gem shape: the native extension + the bundled cdylib ship.
has_native = spec.files.any? { |f| f.include?("fontisan_native") } ||
  File.exist?(File.join(spec.full_gem_path, "lib/fontisan/native"))
failures << "no native extension in the gem" unless has_native
ffi_libs = Dir[File.join(spec.full_gem_path, "lib/fontisan/ffi/**/*.dylib")] +
  Dir[File.join(spec.full_gem_path, "lib/fontisan/ffi/**/*.so")]
failures << "no bundled cdylib in the gem" if ffi_libs.empty?

# 2. The flip: with FONTISAN_ENGINE unset, glyph_ids + outline_hashes serve
#    through native/ffi (NOT ruby).
%w[glyph_ids outline_hashes].each do |op|
  ENV.delete("FONTISAN_ENGINE")
  Fontisan::Engine.reset!
  if op == "glyph_ids"
    Fontisan::Reference.glyph_ids(File.join(fonts, "NotoSans-Regular.ttf"), text: "AB")
  else
    Fontisan::Reference.outline_hashes(File.join(fonts, "NotoSans-Regular.ttf"), index: 0)
  end
  tier = Fontisan::Engine.served_by(op.to_sym).to_s
  failures << "auto #{op} served by #{tier} (want native or ffi)" unless %w[native ffi].include?(tier)
end

# 3. The new capabilities through the engine tier.
ENV["FONTISAN_ENGINE"] = "native"
Fontisan::Engine.reset!
oh = Fontisan::Reference.outline_hashes(File.join(fonts, "NotoSans-Regular.ttf"))
failures << "outline_hashes kind #{oh['kind'].inspect}" unless oh["kind"] == "glyf"
begin
  gid = Fontisan::Reference.glyph_ids(File.join(fonts, "TestTTC.ttc"), text: "AB")
  failures << "collection glyph_ids not an Array: #{gid.inspect[0, 40]}" unless gid.is_a?(Array)
rescue Fontisan::Error
  # The face-0 cmap lookup ran (TestTTC face 0 has no A/B): the engine
  # served the collection, and its no-match error equals Ruby's.
end
d = Fontisan::Reference.read(File.join(fonts, "TestDFONT.dfont"))
failures << "dfont read format #{d[0]['format'].inspect}" unless d[0]["format"] == "dfont"

Dir.mktmpdir do |dir|
  r = Fontisan::Reference.convert(File.join(fonts, "TestTTF.ttf"), to: :svg,
                                                                   output: File.join(dir, "o.svg"))
  failures << "convert svg failed" unless r[:success]
  svg = File.binread(File.join(dir, "o.svg"))
  failures << "svg missing glyphs" unless svg.include?("<glyph ") && svg.start_with?("<?xml")
end

# 4. Type 1 surfaces (#192 gap 4): the corpus PFB serves the measured
#    NoMethodError-shaped surface through the engine tier; scan keeps Ruby.
#    The fontisan corpus keeps it under fonttools-test-t1-pfb/, the
#    engine-side corpus snapshot directly under fonts/.
pfb = [File.join(fonts, "fonttools-test-t1-pfb/TestT1-Regular.pfb"),
       File.join(fonts, "TestT1-Regular.pfb")].find { |f| File.file?(f) }
failures << "no corpus PFB under #{fonts}" unless pfb
begin
  Fontisan::Reference.read(pfb)
  failures << "t1 read did not raise"
rescue Fontisan::InvalidFontError => e
  failures << "t1 read surface: #{e.message[0, 80]}" unless
    e.message.include?("undefined method 'has_table?' for an instance of Fontisan::Type1Font")
  unless e.cause.is_a?(NoMethodError)
    failures << "t1 read cause #{e.cause.class}"
  end
end
Fontisan::Reference.scan([pfb])
failures << "t1 scan served_by #{Fontisan::Engine.served_by(:scan)} (want ruby)" unless
  Fontisan::Engine.served_by(:scan) == :ruby
begin
  Fontisan::Reference.audit(pfb)
rescue Fontisan::InvalidFontError
  nil
end
failures << "t1 audit served_by #{Fontisan::Engine.served_by(:audit)} (want native)" unless
  Fontisan::Engine.served_by(:audit) == :native

if failures.empty?
  puts "RELEASE CONTENT ASSERTIONS PASS (#{version})"
else
  puts "FAILURES:"
  failures.each { |f| puts "  #{f}" }
  exit 1
end
