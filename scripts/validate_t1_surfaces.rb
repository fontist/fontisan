# frozen_string_literal: true

# Type 1 surface validation (#192 gap 4 stage 1): every op on the corpus PFB
# raises the measured Ruby surface through both tiers, byte-identical.
require "fontisan"

FONT = File.expand_path("../../fontisan-rs/.corpus/fontisan/corpus/fonts/TestT1-Regular.pfb", __dir__)
failures = []

EXPECTED = {
  read: ["Fontisan::InvalidFontError",
         /Malformed font data \(NoMethodError\): undefined method 'has_table\?' for an instance of Fontisan::Type1Font/],
  audit: ["Fontisan::InvalidFontError",
          /undefined method 'has_table\?' for an instance of Fontisan::Type1Font/],
  outline_hashes: ["Fontisan::InvalidFontError",
                   /undefined method 'has_table\?' for an instance of Fontisan::Type1Font/],
  glyph_ids: ["Fontisan::InvalidFontError",
              /undefined method 'table' for an instance of Fontisan::Type1Font/],
  subset: ["Fontisan::InvalidFontError",
           /undefined method 'table' for an instance of Fontisan::Type1Font/],
  instance: ["Fontisan::InvalidFontError",
             /undefined method 'table_data' for an instance of Fontisan::Type1Font/],
}.freeze

def outcome(tier, operation, path, **)
  ENV["FONTISAN_ENGINE"] = tier
  Fontisan::Engine.reset!
  Fontisan::Reference.public_send(operation, path, **)
  :ok
rescue StandardError, ScriptError => e
  "#{e.class}: #{e.message}"
end

def served_scan(tier, path)
  ENV["FONTISAN_ENGINE"] = tier
  Fontisan::Engine.reset!
  Fontisan::Engine.scan([path])
  Fontisan::Engine.served_by(:scan).to_s
end

# Returns [served_by(:audit_dir), row_ok]: the walk serves through the tier
# and its single Type 1 row is handed back to Ruby (Ruby's audit raises, the
# walk records the error row, the tag reads :ruby).
def served_audit_dir(tier, path)
  ENV["FONTISAN_ENGINE"] = tier
  Fontisan::Engine.reset!
  require "tmpdir"
  require "fileutils"
  entries = Dir.mktmpdir("t1-audit") do |dir|
    FileUtils.cp(path, dir)
    Fontisan::Engine.audit_dir(dir)
  end
  entry = entries.first || {}
  ok = entry["served_by"] == "ruby" &&
    entry.dig("error", "message").to_s.include?("undefined method 'has_table?'")
  [Fontisan::Engine.served_by(:audit_dir).to_s, ok]
end

%w[native ffi].each do |tier|
  EXPECTED.each do |operation, (klass, message)|
    opts = if %i[glyph_ids subset].include?(operation)
             { text: "AB" }
           elsif operation == :instance
             { coords: { "wght" => 500 } }
           elsif operation == :outline_hashes
             { index: 0 }
           else
             {}
           end
    got = outcome(tier, operation, FONT, **opts)
    ok = got.start_with?(klass) && got.match?(message)
    failures << "#{tier} #{operation}: #{got[0, 140]}" unless ok
    next if operation == :read

    served = if %i[glyph_ids subset].include?(operation)
               ENV["FONTISAN_ENGINE"] = tier
               Fontisan::Engine.reset!
               begin
                 Fontisan::Reference.public_send(operation, FONT, **opts)
               rescue StandardError
                 nil
               end
               Fontisan::Engine.served_by(operation).to_s
             else
               tier
             end
    failures << "#{tier} #{operation} served_by #{served}" unless served == tier
  end

  # convert keeps Type 1 with Ruby, which now converts it for real: the
  # corpus PFB converts to a loadable TTF (sfnt magic 00 01 00 00).
  require "tmpdir"
  ENV["FONTISAN_ENGINE"] = tier
  Fontisan::Engine.reset!
  converted = Dir.mktmpdir("t1-conv") do |dir|
    out = File.join(dir, "out.ttf")
    Fontisan::Reference.convert(FONT, to: :ttf, output: out)
    File.binread(out)
  end
  served = Fontisan::Engine.served_by(:convert).to_s
  failures << "#{tier} convert served_by #{served}" unless served == "ruby"
  failures << "#{tier} convert produced #{converted.bytesize} bytes, head #{converted[0, 4].inspect}" unless
    converted[0, 4] == "\x00\x01\x00\x00"

  # scan keeps its Ruby rows (the goldens record Ruby's); audit_dir serves
  # the walk through the tier and hands the Type 1 row back to Ruby.
  outcome(tier, :scan, [FONT])
  served = served_scan(tier, FONT)
  failures << "#{tier} scan served_by #{served}" unless served == "ruby"

  served, row_ok = served_audit_dir(tier, FONT)
  failures << "#{tier} audit_dir served_by #{served}" unless served == tier
  failures << "#{tier} audit_dir row not handed back to Ruby" unless row_ok
end

if failures.empty?
  puts "TYPE 1 SURFACES PASS (native + ffi)"
else
  puts "FAILURES (#{failures.length}):"
  failures.first(10).each { |f| puts "  #{f}" }
  exit 1
end
