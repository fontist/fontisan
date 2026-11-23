# frozen_string_literal: true

require "json"
require_relative "support/corpus_paths"
require_relative "../../scripts/corpus/generate_scan_goldens"

# glyph_ids tier parity (fontisan#192 gap 1). Under a forced tier, every
# ci-tier font's glyph_ids must equal the Ruby tier's — same value, or the
# same error class and message — and the row must be served by the expected
# tier: the forced engine for engine-readable single fonts, Ruby for
# collections and the handed formats (dfont, Type 1, non-fonts), which the
# engine declines by design. Runs in every parity cell, strict mode on, so a
# byte difference or a silent fallback fails the cell.
RSpec.describe "glyph_ids tier parity" do # rubocop:disable RSpec/SpecFilePathFormat
  let(:entries) { ScanGoldens.entries("ci") }
  let(:probe_text) { "AB a." }

  def with_tier(name)
    ENV["FONTISAN_ENGINE"] = name
    Fontisan::Engine.reset!
    yield
  ensure
    ENV["FONTISAN_ENGINE"] = nil
    Fontisan::Engine.reset!
  end

  def outcome(path)
    Fontisan::Reference.glyph_ids(path, text: probe_text)
    :ok
  rescue StandardError, ScriptError => e
    "#{e.class}: #{e.message}"
  end

  # The tier the call must be served by: Ruby decides everything the engine
  # declines (collections, dfont, Type 1, non-fonts), else the forced tier —
  # or, for auto, whatever the engine itself resolves for this font.
  # +forced+ is a parameter, not the let: a def method cannot see the
  # example's local, and the let's first evaluation timing was exactly the
  # bug that mis-computed want for served-by assertions.
  def expected_tier(path, forced)
    # options included: glyph_ids declines collections via glyph_ids_options?
    return Fontisan::Engine.resolve(:glyph_ids, path, text: probe_text).to_s if forced == "auto"

    format = Fontisan::FontLoader.detect_format(path)
    single = format && !%w[dfont pfa pfb ttc otc woff2_collection].include?(format.to_s)
    single ? forced : "ruby"
  end

  def brotli?
    Fontisan::Utilities::BrotliWrapper.available?
  rescue StandardError, ScriptError
    false
  end

  it "matches the Ruby tier's outcome on every ci-tier font, served by the expected tier" do
    # The tier the cell is driving, derived from the ENGINE's own resolved
    # config rather than ENV: the jruby cell mixes MRI and JRuby installs,
    # and ENV delivery to `ruby -S rspec` has proven unreliable there.
    # With FONTISAN_ENGINE unset, setup! resolves auto (ffi on JRuby —
    # there is no native tier), which is exactly what the cell drives.
    forced = Fontisan::Engine.setup!.selection.to_s
    forced = "auto" if forced == "auto" # setup! under unset env resolves auto
    entries.each do |entry|
      path = ScanGoldens.font_path(entry)
      want_tier = expected_tier(path, forced)
      expected = nil

      with_tier("ruby") { expected = outcome(path) }
      with_tier(forced) do
        got = outcome(path)
        # On a brotli-less platform (the java gem on JRuby) a WOFF2
        # glyph_ids raises Woff2Unavailable at setup under ANY tier — the
        # facade's documented gate — and served_by stays nil. Both tiers
        # raise the identical error, so the outcome assertion below already
        # proves parity; the served_by expectation applies to brotli-ful
        # platforms only (#192 tracks the JRuby env/engine routing notes).
        java_woff2 = !brotli? && File.binread(path, 4) == "wOF2"
        expect(got).to eq(expected),
                       "#{entry['id']} differs under #{forced}: #{got.inspect} vs #{expected.inspect}"
        unless java_woff2
          served = Fontisan::Engine.served_by(:glyph_ids).to_s
          head = File.binread(path, 8).to_s
          expect(served).to eq(want_tier),
                            "#{entry['id']} served_by #{served.inspect}, want #{want_tier.inspect} " \
                            "(#{forced}; env now #{ENV['FONTISAN_ENGINE'].inspect}; " \
                            "format #{Fontisan::FontLoader.detect_format(path).inspect}, " \
                            "head #{head.unpack1('A8').inspect})"
        end
      end
    end
  end

  it "strict mode serves every engine-readable font without falling back" do
    forced = "auto" # the strict example drives whatever the unset env resolves
    ENV["FONTISAN_ENGINE_STRICT"] = "1"
    entries.each do |entry|
      path = ScanGoldens.font_path(entry)
      want_tier = expected_tier(path, forced)
      next if want_tier == :ruby

      with_tier(forced) do
        expect { outcome(path) }.not_to raise_error(Fontisan::Engine::TierUnavailable),
                                        "#{entry['id']} fell back in strict mode"
      end
    end
  end
end
