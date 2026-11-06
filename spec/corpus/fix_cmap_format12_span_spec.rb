# frozen_string_literal: true

require_relative "support/corpus_paths"

RSpec.describe "cmap format 12 group spanning the u32 range" do
  let(:path) { File.join(CorpusPaths::ROOT, "corpus", "derived", "malformed-fuzz-cmap12-u32-span.ttf") }

  it "maps at most the Unicode range and returns promptly" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    mappings = Fontisan::FontLoader.load(path, mode: :full).table("cmap").unicode_mappings

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
    expect(mappings.keys.max).to eq(0x10FFFF)
  end
end
