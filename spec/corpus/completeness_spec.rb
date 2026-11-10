# frozen_string_literal: true

require_relative "support/corpus_paths"
require_relative "../../scripts/corpus/generate_goldens"

# The golden files must equal (every non-malformed manifest font of the tier)
# x (every read op), plus the swallow cases. The large tier runs with TIER=large.
RSpec.describe "read golden completeness" do
  let(:tier) { ENV.fetch("TIER", "ci") }
  let(:root) { CorpusGoldens::ROOT }
  let(:ops) { %w[metadata/lazy metadata/eager full/lazy full/eager] }

  let(:files) do
    Dir.glob(File.join(CorpusGoldens.golden_dir(tier), "*.json")).map { |p| File.basename(p, ".json") }.sort
  end

  it "has exactly one golden per manifest font" do
    expect(files).to eq(CorpusGoldens.entries(tier).map { |e| e["id"] }.sort)
  end

  it "covers every read op and both audit modes in each golden" do
    incomplete = files.reject do |id|
      doc = JSON.parse(File.read(CorpusGoldens.golden_path(tier, id)))
      doc["read"].keys.sort == ops.sort && doc["audit"].keys.sort == %w[default validate]
    end
    expect(incomplete).to eq([])
  end

  it "has a golden and an input font for every swallow case", if: ENV.fetch("TIER", "ci") == "ci" do
    names = CorpusGoldens::SWALLOW_CASES.keys.sort
    dir = CorpusGoldens::SWALLOW_DIR
    expect(Dir.children(dir).sort).to eq(names.flat_map { |n| ["#{n}.json", "#{n}.ttf"] }.sort)
  end

  it "has the two post-Phase-0 divergence goldens", if: ENV.fetch("TIER", "ci") == "ci" do
    expect(Dir.children(CorpusGoldens::DIVERGE_DIR).sort).to eq(%w[bad-checksum-validate.json woff1-mode.json])
  end

  describe "TRIAGE.md" do
    let(:triage) { File.read(File.join(root, "corpus", "TRIAGE.md")) }
    let(:listed) { triage.scan(/^\| ([A-Z0-9-]+) \| known_reference_bug \|/).flatten.sort }
    let(:used) do
      Dir.glob([File.join(CorpusGoldens.golden_dir(tier), "*.json"),
                File.join(CorpusGoldens::DIVERGE_DIR, "*.json")])
        .flat_map { |p| JSON.parse(File.read(p)).fetch("known_reference_bug") }.uniq.sort
    end

    it "lists every known_reference_bug id the goldens use" do
      expect(used - listed).to eq([])
    end

    it "uses every known_reference_bug id TRIAGE.md lists (ci tier)", if: ENV.fetch("TIER", "ci") == "ci" do
      expect(listed - used).to eq([])
    end

    it "marks every other entry as fixed" do
      statuses = triage.scan(/^\| [A-Z0-9-]+ \| (\S+) \|/).flatten.uniq
      expect(statuses - %w[fixed known_reference_bug]).to eq([])
    end
  end
end
