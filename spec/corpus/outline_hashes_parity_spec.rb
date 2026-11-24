# frozen_string_literal: true

require "json"
require_relative "support/corpus_paths"
require_relative "../../scripts/corpus/generate_scan_goldens"

# outline_hashes tier parity (#192 gap 2). Under a forced tier, every ci-tier
# font's outline_hashes must equal the Ruby tier's — same value, or the same
# error class and message — and the row must be served by the expected tier.
# Unlike glyph_ids, the engine reads collections AND dfonts here (gap 5), so
# only Type 1 and unknown formats stay with Ruby; and the java-gem corner has
# no collection split: the engine decodes every WOFF2 natively, so under an
# engine tier any WOFF2 must engage. Runs in every parity cell, strict mode
# on, so a byte difference or a silent fallback fails the cell.
RSpec.describe "outline_hashes tier parity" do # rubocop:disable RSpec/SpecFilePathFormat
  let(:entries) { ScanGoldens.entries("ci") }

  def with_tier(name)
    ENV["FONTISAN_ENGINE"] = name
    Fontisan::Engine.reset!
    yield
  ensure
    ENV["FONTISAN_ENGINE"] = nil
    Fontisan::Engine.reset!
  end

  def outcome(path)
    Fontisan::Reference.outline_hashes(path, index: 0)
    :ok
  rescue StandardError, ScriptError => e
    "#{e.class}: #{e.message}"
  end

  def expected_tier(path, forced)
    if forced == "auto"
      # resolve raises the WOFF2 gate only when the resolved tier IS ruby
      # (require_woff2_support! fires at tier == :ruby): a brotli-less
      # platform's woff2 wants "ruby" with served_by nil, not a raise out of
      # the expectation computation.
      begin
        Fontisan::Engine.resolve(:outline_hashes, path, index: 0).to_s
      rescue Fontisan::Engine::Woff2Unavailable
        "ruby"
      end
    else
      format = Fontisan::FontLoader.detect_format(path)
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
    # Derived from the ENGINE's own resolved config (see the glyph_ids spec:
    # ENV delivery to `ruby -S rspec` is unreliable in the jruby cell).
    forced = Fontisan::Engine.setup!.selection.to_s
    entries.each do |entry|
      path = ScanGoldens.font_path(entry)
      want_tier = expected_tier(path, forced)
      expected = nil

      with_tier("ruby") { expected = outcome(path) }
      with_tier(forced) do
        got = outcome(path)
        head = File.binread(path, 8).to_s
        # On a brotli-less platform the Ruby tier cannot read ANY woff2 —
        # the gate fires before anything is served. The engine decodes the
        # woff2 itself, so under an engine tier the one wrong answer is the
        # gate (the tier never engaged); under forced ruby the outcome
        # equals the baseline and served_by stays nil.
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
          served = Fontisan::Engine.served_by(:outline_hashes).to_s
          expect(served).to eq(want_tier),
                            "#{entry['id']} served_by #{served.inspect}, want #{want_tier.inspect} " \
                            "(#{forced}; format #{Fontisan::FontLoader.detect_format(path).inspect})"
        end
      end
    end
  end
end
