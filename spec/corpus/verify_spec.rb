# frozen_string_literal: true

require "json"
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

  describe "post-Phase-0 divergence goldens" do
    let(:dir) { CorpusGoldens::DIVERGE_DIR }

    it "pins the WOFF1 mode each variant echoes, with no same_as dedupe" do
      doc = JSON.parse(File.read(File.join(dir, "woff1-mode.json")))
      expect(doc["cases"].keys).to match_array(%w[fonttools-test-woff source-sans-3-regular-ttf-woff
                                                  source-sans-3-regular-otf-woff])
      doc["cases"].each_value do |c|
        expect(c["read"].keys).to match_array(%w[metadata/lazy metadata/eager full/lazy full/eager])
        c["read"].each do |variant, result|
          expect(result["ok"].map { |face| face["mode"] }.uniq).to eq([variant.split("/").first])
        end
      end
    end

    it "pins the table_directory crash of validate: true on a bad checksum" do
      doc = JSON.parse(File.read(File.join(dir, "bad-checksum-validate.json")))
      expect(doc["known_reference_bug"]).to eq(["CHECKSUM-BINDATA"])
      report = doc.dig("audit", "validate", "ok").first
      expect(report.fetch("validation_summary")).to include("fatal_count" => 1, "error_count" => 0, "passed" => false)
      expect(report.fetch("validation_issues").map { |i| i["message"] })
        .to include("Check table_directory failed to execute: ArgumentError: wrong number of arguments (given 1, expected 0)")
    end

    it "fails verify when a WOFF1 mode is mutated" do
      path = File.join(dir, "woff1-mode.json")
      original = File.binread(path)
      mutated = original.sub('"mode": "full"', '"mode": "metadata"')
      expect(mutated).not_to eq(original)
      allow(File).to receive(:binread).and_call_original
      allow(File).to receive(:binread).with(path).and_return(mutated)
      expect(CorpusGoldens.verify("ci").grep(/golden differs.*woff1-mode/).size).to eq(1)
    end
  end
end
