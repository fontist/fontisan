# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "support/corpus_paths"
require_relative "../../scripts/corpus/generate_goldens"

RSpec.describe "corpus:verify read goldens" do
  it "finds no difference between the committed goldens and fresh output" do
    expect(CorpusGoldens.verify("ci")).to eq([])
  end

  it "fails when one byte of a golden changes" do
    Dir.mktmpdir("goldens") do |dir|
      FileUtils.cp_r(CorpusGoldens.golden_dir("ci"), dir)
      victim = File.join(dir, "read", "fonttools-test-ttf.json")
      bytes = File.binread(victim)
      bytes.setbyte(bytes.index("\"schema\": 1") + 10, "2".ord)
      File.binwrite(victim, bytes)

      allow(CorpusGoldens).to receive(:golden_dir).with("ci").and_return(File.join(dir, "read"))
      allow(CorpusGoldens).to receive(:golden_path).and_wrap_original do |_m, _tier, id|
        File.join(dir, "read", "#{id}.json")
      end

      problems = CorpusGoldens.verify("ci").grep(/golden differs/)
      expect(problems.size).to eq(1)
      expect(problems.first).to include("fonttools-test-ttf.json")
    end
  end
end
