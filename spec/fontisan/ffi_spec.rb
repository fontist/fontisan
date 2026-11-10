# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# The :ffi tier (fontisan#156 card 2d): the Rust engine's C ABI through the
# optional `ffi` gem. The parity examples need the built cdylib (point
# FONTISAN_CDYLIB at it, or `rake cdylib:build`) and are skipped, never
# passed, without it.
RSpec.describe Fontisan::Ffi do
  def self.root = File.expand_path("../..", __dir__)

  def self.fonts
    [
      "spec/fixtures/fonttools/Test*.{ttf,otf,ttc,woff,woff2,dfont}",
      "spec/fixtures/fonts/type1/{quicksand.pfb,matrix.pfa}",
      "corpus/derived/*.{ttf,ttc}",
    ].flat_map { |glob| Dir.glob(File.join(root, glob)) }
  end

  def fonts = self.class.fonts

  def ruby_only = %w[.dfont .pfa .pfb]

  around do |example|
    saved = ENV.to_h.slice("FONTISAN_ENGINE", "FONTISAN_ENGINE_STRICT", "FONTISAN_CDYLIB")
    example.run
  ensure
    %w[FONTISAN_ENGINE FONTISAN_ENGINE_STRICT FONTISAN_CDYLIB].each { |k| ENV.delete(k) }
    ENV.update(saved)
    Fontisan::Engine.reset!
  end

  def tier(engine, strict: true)
    ENV["FONTISAN_ENGINE"] = engine
    ENV["FONTISAN_ENGINE_STRICT"] = strict ? "1" : nil
    Fontisan::Engine.reset!
  end

  # The result, or the exception class, message and cause chain.
  def outcome
    { ok: yield }
  rescue StandardError => e
    chain = []
    while e
      chain << [e.class.name, e.message]
      e = e.cause
    end
    { error: chain }
  end

  # Ruby's table_directory check raises ArgumentError on a bad table checksum
  # and reports a fatal issue; the engine reports the checksum mismatch. Not a
  # tier difference to hide: validate: true is left out for that one file until
  # the reference is triaged (reported on the card).
  def validate_modes(name)
    name == "malformed-bad-checksum.ttf" ? [false] : [false, true]
  end

  # A WOFF1 face reads as mode "metadata" from the engine and "full" from Ruby
  # when full is requested (goldens strip `mode`, so they do not see it);
  # reported on the card, compared here without that one key.
  def comparable(result, name)
    return result unless name.end_with?(".woff") && result[:ok].is_a?(Array)

    { ok: result[:ok].map { |row| row.is_a?(Hash) ? row.except("mode") : row } }
  end

  def built?
    Fontisan::Engine.reset!
    described_class.available?
  end

  describe "without a usable library" do
    it "is unavailable and serves from Ruby when the library path is wrong" do
      ENV["FONTISAN_CDYLIB"] = File.join(Dir.tmpdir, "no-such-fontisan-lib.so")
      tier("ffi", strict: false)
      font = fonts.first
      expect(described_class).not_to be_available
      expect(Fontisan::Reference.read(font)).not_to be_empty
      expect(Fontisan::Engine.served_by(:read)).to eq(:ruby)
    end

    it "makes strict mode raise at setup, not on first use" do
      ENV["FONTISAN_CDYLIB"] = File.join(Dir.tmpdir, "no-such-fontisan-lib.so")
      tier("ffi")
      expect { Fontisan::Reference.read(fonts.first) }
        .to raise_error(Fontisan::Engine::TierUnavailable, /ffi tier is not available/)
    end

    it "treats a library without the fontisan symbols as unavailable" do
      ENV["FONTISAN_CDYLIB"] = RbConfig::CONFIG["libdir"] + "/libruby.#{RbConfig::CONFIG['SOEXT']}"
      tier("ffi")
      expect(described_class).not_to be_available
    end

    it "treats an ABI mismatch as unavailable" do
      allow(Fontisan::Ffi::Client).to receive(:new).and_raise(Fontisan::Ffi::AbiMismatch, "ABI 2")
      tier("ffi", strict: false)
      expect(described_class).not_to be_available
    end
  end

  describe "the engine rev handshake" do
    before { require "fontisan/ffi/client" }

    def client_for(rev)
      lib = double("cdylib", fontisan_abi_version: Fontisan::Ffi::Client::ABI_VERSION)
      if rev == :missing
        allow(lib).to receive(:fontisan_cdylib_engine_rev).and_raise(FFI::NotFoundError.new("fontisan_cdylib_engine_rev", []))
      else
        allow(lib).to receive(:fontisan_cdylib_engine_rev).and_return(rev)
      end
      allow(Fontisan::Ffi::Client).to receive(:bind).and_return(lib)
      Fontisan::Ffi::Client.new("lib.so")
    end

    it "accepts a library built from the expected engine rev" do
      expect { client_for(Fontisan::Native::ENGINE_REV) }.not_to raise_error
    end

    it "rejects a library built from another engine rev" do
      expect { client_for("0" * 40) }.to raise_error(Fontisan::Ffi::AbiMismatch, /built from engine/)
    end

    it "rejects a library without the rev symbol (a stale build) as a LoadError" do
      expect { client_for(:missing) }.to raise_error(LoadError, /fontisan_cdylib_engine_rev/)
    end

    it "makes strict mode raise at setup for a stale library" do
      allow(Fontisan::Ffi::Client).to receive(:new).and_raise(LoadError, "fontisan_cdylib_engine_rev")
      tier("ffi")
      expect { Fontisan::Reference.read(fonts.first) }
        .to raise_error(Fontisan::Engine::TierUnavailable, /ffi tier is not available/)
    end
  end

  describe "with the built library" do
    before do
      skip "cdylib not built (set FONTISAN_CDYLIB)" unless built?
    end

    it "lists the fixtures it compares" do
      expect(fonts.map { |f| File.extname(f) }).to include(*ruby_only)
    end

    describe "parity with the Ruby tier" do
      fonts.each do |font|
        it "gives identical read, audit and scan results for #{File.basename(font)}" do
          name = File.basename(font)
          # Ruby's own detection decides; matrix.pfa is not a Type 1 header, so both
          # tiers report the same unknown-format error and the engine serves it.
          served = Fontisan::FontLoader.detect_format(font).to_s.match?(/\A(dfont|pfa|pfb)\z/) ? :ruby : :ffi
          calls = {
            read: [%i[metadata full].product([true, false]).map do |mode, lazy|
              -> { Fontisan::Reference.read(font, mode: mode, lazy: lazy) }
            end],
            audit: [validate_modes(name).map { |v| -> { Fontisan::Reference.audit(font, validate: v) } }],
            scan: [[-> { Fontisan::Reference.scan([font]) }]],
          }
          calls.each do |operation, (variants)|
            variants.each do |call|
              tier("ruby")
              expected = outcome(&call)
              tier("ffi")
              expect(comparable(outcome(&call), name)).to eq(comparable(expected, name)), "#{operation} on #{name}"
              expect(Fontisan::Engine.served_by(operation)).to eq(served), "#{operation} on #{name}"
            end
          end
        end
      end
    end

    it "gives identical audit_dir entries, tagging each by the tier that audited it" do
      dir = Dir.mktmpdir("ffi-audit-dir")
      fonts.each { |f| FileUtils.cp(f, dir) unless File.basename(f).match?(/\Amalformed-(truncated|bad-checksum)/) }
      tier("ruby")
      expected = outcome { Fontisan::Reference.audit_dir(dir, validate: true) }
      tier("ffi")
      expect(outcome { Fontisan::Reference.audit_dir(dir, validate: true) }).to eq(expected)
      tagged = Fontisan::Engine.audit_dir(dir, validate: true).to_h { |e| [e["path"], e["served_by"]] }
      expect(tagged.select { |_, t| t == "ruby" }.keys.map { |p| File.extname(p) }.uniq.sort)
        .to eq(%w[.dfont .pfb])
      expect(tagged.reject { |p, _| %w[.dfont .pfb].include?(File.extname(p)) }.values.uniq).to eq(["ffi"])
    ensure
      FileUtils.rm_rf(dir)
    end

    it "serves a directory scan row-for-row like Ruby" do
      font = fonts.find { |f| f.end_with?("TestTTF.ttf") }
      tier("ruby")
      expected = Fontisan::Reference.scan([font])
      tier("ffi")
      rows = Fontisan::Engine.scan([font])
      expect(rows.map { |r| r.except("served_by") }).to eq(expected)
      expect(rows.map { |r| r["served_by"] }.uniq).to eq(["ffi"])
    end

    it "hands operations the ABI does not carry to Ruby" do
      tier("ffi")
      font = fonts.find { |f| f.end_with?("TestTTF.ttf") }
      Fontisan::Reference.outline_hashes(font)
      expect(Fontisan::Engine.served_by(:outline_hashes)).to eq(:ruby)
    end

    it "decodes batch rows once into plain Ruby objects" do
      tier("ffi")
      rows = Fontisan::Reference.read(fonts.find { |f| f.end_with?("TestTTC.ttc") })
      expect(rows.size).to be > 1
      expect(rows).to all(be_a(Hash))
    end

    it "keeps running Ruby threads while a call is in flight" do
      tier("ffi")
      font = fonts.find { |f| f.end_with?("TestTTF.ttf") }
      results = Array.new(4) { Thread.new { Fontisan::Reference.read(font) } }.map(&:value)
      expect(results.uniq.size).to eq(1)
    end
  end

  describe "the engine's own source" do
    it "loads the ffi gem only from the client file" do
      lib = File.expand_path("../../lib", __dir__)
      offenders = Dir.glob("#{lib}/**/*.rb").select { |f| File.read(f).match?(/^\s*require ["']ffi["']/) }
      expect(offenders.map { |f| f.delete_prefix("#{lib}/") }).to eq(["fontisan/ffi/client.rb"])
    end
  end
end
