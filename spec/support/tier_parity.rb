# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Runs a block under one engine tier, strictly for native and ffi so a tier that
# fell back to Ruby cannot pass for the tier under test (fontist/fontisan#159).
module TierParity
  TIERS = %w[ruby native ffi].freeze

  def with_engine(selection)
    saved = ENV.to_h.slice("FONTISAN_ENGINE", "FONTISAN_ENGINE_STRICT")
    ENV["FONTISAN_ENGINE"] = selection
    ENV["FONTISAN_ENGINE_STRICT"] = selection == "ruby" ? nil : "1"
    Fontisan::Engine.reset!
    yield
  ensure
    ENV.delete("FONTISAN_ENGINE")
    ENV.delete("FONTISAN_ENGINE_STRICT")
    ENV.update(saved)
    Fontisan::Engine.reset!
  end

  # [class, message] of the StandardError the block raises, else nil.
  def failure
    yield
    nil
  rescue StandardError => e
    [e.class, e.message]
  end

  def skip_unless_built(tier)
    mod = { "native" => Fontisan::Native, "ffi" => Fontisan::Ffi }[tier]
    skip "#{tier} tier not built (rake compile / rake cdylib:build)" if mod && !mod.available?
  end
end
