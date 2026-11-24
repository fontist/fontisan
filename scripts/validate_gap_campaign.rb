# frozen_string_literal: true

# Cross-tier validation for the gap campaign (#192 gaps 7/2/3/5): every new
# engine capability under native and ffi must equal the Ruby tier's outcome.
require "fontisan"
require "json"
require "fileutils"

FONT = "../fontisan-rs/.corpus/fontisan/corpus/fonts"
OTC = "/tmp/validation-src.otc"

failures = []

def outcome(tier, operation, path, **)
  ENV["FONTISAN_ENGINE"] = tier
  Fontisan::Engine.reset!
  result = Fontisan::Reference.public_send(operation, path, **)
  result.is_a?(String) ? result.bytes : result
rescue StandardError, ScriptError => e
  "#{e.class}: #{e.message}"
end

def served(tier, operation, path, **)
  ENV["FONTISAN_ENGINE"] = tier
  Fontisan::Engine.reset!
  begin
    Fontisan::Reference.public_send(operation, path, **)
  rescue StandardError
    nil
  end
  Fontisan::Engine.served_by(operation).to_s
end

files = Dir.glob("#{FONT}/*").select { |f| File.file?(f) }
# A .otc copy of a ttc exercises the source hint.
FileUtils.cp("#{FONT}/TestTTC.ttc", OTC)

checks = lambda do |tier|
  files.each do |path|
    rel = File.basename(path)

    # outline_hashes: outcome parity + served tier.
    ruby = outcome("ruby", :outline_hashes, path, index: 0)
    got = outcome(tier, :outline_hashes, path, index: 0)
    failures << "#{tier} outline_hashes #{rel}: #{got.inspect[0, 80]} != #{ruby.inspect[0, 80]}" if got != ruby
    next unless File.basename(path) == "TestTTF.ttf"

    served_tier = served(tier, :outline_hashes, path, index: 0)
    failures << "#{tier} outline_hashes served_by #{served_tier}" unless served_tier == tier

    # glyph_ids: outcome parity.
    ruby = outcome("ruby", :glyph_ids, path, text: "AB a.")
    got = outcome(tier, :glyph_ids, path, text: "AB a.")
    failures << "#{tier} glyph_ids #{rel}: #{got.inspect[0, 60]} != #{ruby.inspect[0, 60]}" if got != ruby
  end

  # dfont read parity (full doc).
  ruby = outcome("ruby", :read, "#{FONT}/TestDFONT.dfont")
  got = outcome(tier, :read, "#{FONT}/TestDFONT.dfont")
  failures << "#{tier} dfont read mismatch" if got != ruby

  # convert → svg: byte parity against the Ruby tier (small font for speed).
  ruby = outcome("ruby", :convert, "#{FONT}/TestTTF.ttf", to: :svg,
                                                          output: "/tmp/v-ruby.svg")
  got = outcome(tier, :convert, "#{FONT}/TestTTF.ttf", to: :svg,
                                                       output: "/tmp/v-#{tier}.svg")
  same = ruby.is_a?(Hash) && ruby[:success] && got.is_a?(Hash) && got[:success] &&
    File.binread("/tmp/v-ruby.svg") == File.binread("/tmp/v-#{tier}.svg")
  failures << "#{tier} convert svg differs" unless same

  # convert .otc → :otc (same-type copy) vs Ruby.
  ruby = outcome("ruby", :convert, OTC, to: :otc, output: "/tmp/v-ruby.otc")
  got = outcome(tier, :convert, OTC, to: :otc, output: "/tmp/v-#{tier}.otc")
  same = ruby.is_a?(Hash) && ruby[:success] && got.is_a?(Hash) && got[:success] &&
    File.binread("/tmp/v-ruby.otc") == File.binread("/tmp/v-#{tier}.otc")
  failures << "#{tier} convert .otc→otc differs: #{ruby.inspect[0, 60]} vs #{got.inspect[0, 60]}" unless same

  # extract from a .otc names members .otf.
  served(tier, :extract, OTC, index: 0, output_dir: "/tmp/v-extract-#{tier}")
  name = Dir["/tmp/v-extract-#{tier}/*"].map { |f| File.basename(f) }.first.to_s
  failures << "#{tier} extract .otc basename #{name.inspect} (want .otf)" unless name.end_with?(".otf")

  # Collections through the face-0 ops: glyph_ids, subset (bytes), instance
  # (bytes) must equal the Ruby tier's.
  %w[TestTTC.ttc TestWOFF2.woff2].each do |collection|
    path = "#{FONT}/#{collection}"
    next unless File.file?(path)

    ruby = outcome("ruby", :glyph_ids, path, text: "AB a.")
    got = outcome(tier, :glyph_ids, path, text: "AB a.")
    failures << "#{tier} glyph_ids #{collection}: #{got.inspect[0, 50]} vs #{ruby.inspect[0, 50]}" if ruby != got

    ruby = outcome("ruby", :subset, path, text: "AB", profile: "web")
    got = outcome(tier, :subset, path, text: "AB", profile: "web")
    same = ruby.is_a?(String) && got.is_a?(String) && ruby == got
    failures << "#{tier} subset #{collection} bytes differ" unless same

    ruby = outcome("ruby", :instance, path, coords: { "wght" => 500 })
    got = outcome(tier, :instance, path, coords: { "wght" => 500 })
    same = ruby == got
    failures << "#{tier} instance #{collection}: #{got.inspect[0, 60]} vs #{ruby.inspect[0, 60]}" unless same
  end

  # A dfont through the face-0 ops.
  ruby = outcome("ruby", :subset, "#{FONT}/TestDFONT.dfont", text: "AB", profile: "web")
  got = outcome(tier, :subset, "#{FONT}/TestDFONT.dfont", text: "AB", profile: "web")
  failures << "#{tier} subset dfont: #{got.inspect[0, 60]} vs #{ruby.inspect[0, 60]}" if ruby != got
end

checks.call("native")
checks.call("ffi")

if failures.empty?
  puts "ALL CROSS-TIER CHECKS PASS (native + ffi)"
else
  puts "FAILURES (#{failures.length}):"
  failures.first(12).each { |f| puts "  #{f}" }
  exit 1
end
