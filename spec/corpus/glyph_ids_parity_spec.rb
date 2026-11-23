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
  let(:forced) { ENV.fetch("FONTISAN_ENGINE", "ruby") }
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
  # declines (collections, dfont, Type 1, non-fonts), else the forced tier.
  def expected_tier(path)
    format = Fontisan::FontLoader.detect_format(path)
    single = format && !%w[dfont pfa pfb ttc otc].include?(format.to_s)
    single ? forced.to_sym : :ruby
  end

  # On a platform without the brotli gem (the java gem on JRuby) the Ruby
  # tier cannot read a WOFF2 at all: resolve raises Woff2Unavailable before
  # anything is served. The ENGINE tier decodes WOFF2 natively, so the
  # forced tier SUCCEEDING there while the Ruby baseline raises is the
  # platform working as designed, not a parity break.
  def ruby_cannot_read_woff2?(path, expected)
    return false unless File.binread(path, 4) == "wOF2"
    return false if brotli?

    expected.is_a?(String) && expected.include?("Woff2Unavailable")
  end

  def brotli?
    Fontisan::Utilities::BrotliWrapper.available?
  rescue StandardError, ScriptError
    false
  end

  it "matches the Ruby tier's outcome on every ci-tier font, served by the expected tier" do
    entries.each do |entry|
      path = ScanGoldens.font_path(entry)
      want_tier = expected_tier(path)
      expected = nil

      with_tier("ruby") { expected = outcome(path) }
      with_tier(forced) do
        got = outcome(path)
        if ruby_cannot_read_woff2?(path, expected)
          expect(got).to eq(:ok), "#{entry['id']} the engine tier should decode the WOFF2: #{got.inspect}"
        else
          expect(got).to eq(expected),
                         "#{entry['id']} differs under #{forced}: #{got.inspect} vs #{expected.inspect}"
        end
        served = Fontisan::Engine.served_by(:glyph_ids)
        head = File.binread(path, 8).to_s
        expect(served).to eq(want_tier),
                          "#{entry['id']} served_by #{served.inspect}, want #{want_tier.inspect} " \
                          "(#{forced}; format #{Fontisan::FontLoader.detect_format(path).inspect}, " \
                          "head #{head.unpack1('A8').inspect})"
      end
    end
  end

  it "strict mode serves every engine-readable font without falling back" do
    ENV["FONTISAN_ENGINE_STRICT"] = "1"
    entries.each do |entry|
      path = ScanGoldens.font_path(entry)
      want_tier = expected_tier(path)
      next if want_tier == :ruby

      with_tier(forced) do
        expect { outcome(path) }.not_to raise_error(Fontisan::Engine::TierUnavailable),
                                        "#{entry['id']} fell back in strict mode"
      end
    end
  end
end
