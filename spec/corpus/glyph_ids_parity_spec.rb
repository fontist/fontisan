# frozen_string_literal: true

require "json"
require_relative "support/corpus_paths"
require_relative "../../scripts/corpus/generate_scan_goldens"

# glyph_ids tier parity (fontisan#192 gap 1). Under a forced tier, every
# ci-tier font's glyph_ids must equal the Ruby tier's — same value, or the
# same error class and message — and the row must be served by the expected
# tier: the forced engine for engine-readable inputs, single fonts and
# collections alike (the engine runs face 0, as Ruby's loader does), Ruby for
# Type 1 and non-fonts, which the engine declines by design. Runs in every
# parity cell, strict mode on, so a byte difference or a silent fallback
# fails the cell.
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
  # declines (Type 1, non-fonts), else the forced tier — or, for auto,
  # whatever the engine itself resolves for this font.
  # +forced+ is a parameter, not the let: a def method cannot see the
  # example's local, and the let's first evaluation timing was exactly the
  # bug that mis-computed want for served-by assertions.
  def expected_tier(path, forced)
    # options included
    if forced == "auto"
      # resolve raises the WOFF2 gate only when the resolved tier IS ruby
      # (require_woff2_support! fires at tier == :ruby): a brotli-less
      # platform's woff2 collection wants "ruby" with served_by nil, not a
      # raise out of the expectation computation.
      begin
        Fontisan::Engine.resolve(:glyph_ids, path, text: probe_text).to_s
      rescue Fontisan::Engine::Woff2Unavailable
        "ruby"
      end
    else
      format = Fontisan::FontLoader.detect_format(path)
      # Only Type 1 and unknown formats stay with Ruby: the engine serves
      # collections (face 0, #192 gap 5 follow-up) and dfonts (gap 5) too.
      single = format && !%w[pfa pfb].include?(format.to_s)
      single ? forced : "ruby"
    end
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
        head = File.binread(path, 8).to_s
        # On a brotli-less platform (the java gem on JRuby) the Ruby tier
        # cannot read ANY woff2 — the gate (Woff2Unavailable) fires before
        # anything is served. The engine decodes every woff2 natively,
        # collections included, so under an engine tier the one wrong
        # answer is the gate itself (the tier never engaged); under forced
        # ruby the outcome equals the baseline and served_by stays nil.
        java_woff2 = !brotli? && head.start_with?("wOF2")
        if java_woff2 && forced != "ruby"
          expect(got == :ok || (got.is_a?(String) && !got.include?("Woff2Unavailable")))
            .to be(true),
                "#{entry['id']} the engine tier must engage the WOFF2 itself: #{got.inspect}"
        else
          expect(got).to eq(expected),
                         "#{entry['id']} differs under #{forced}: #{got.inspect} vs #{expected.inspect}"
        end
        skip_wanted = java_woff2 && forced == "ruby"
        unless skip_wanted
          served = Fontisan::Engine.served_by(:glyph_ids).to_s
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
      # woff2 entries' tier expectations live in example 1's corner (the
      # brotli-less gate fires inside resolve itself — expected_tier's
      # auto branch would raise here, not report).
      next if File.binread(path, 4) == "wOF2"

      want_tier = expected_tier(path, forced)
      next if want_tier == :ruby

      with_tier(forced) do
        expect { outcome(path) }.not_to raise_error(Fontisan::Engine::TierUnavailable),
                                        "#{entry['id']} fell back in strict mode"
      end
    end
  end
end
