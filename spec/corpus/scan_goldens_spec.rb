# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "support/corpus_paths"
require_relative "../../scripts/corpus/generate_scan_goldens"

# corpus/goldens/scan: one scan golden per manifest row (fontist/fontisan#156,
# card 0f). The large tier is generated in the nightly job (TIER=large).
RSpec.describe ScanGoldens do # rubocop:disable RSpec/SpecFilePathFormat
  let(:tier) { ENV.fetch("TIER", "ci") }
  let(:ids) { described_class.entries(tier).map { |e| e["id"] } }
  let(:files) do
    Dir.glob(File.join(described_class.golden_dir(tier), "*.json")).map { |p| File.basename(p, ".json") }.sort
  end

  it "has exactly one golden per manifest row of the tier, malformed included" do
    expect(files).to eq(ids.sort)
    expect(ids).to include("malformed-garbage", "malformed-empty", "fonttools-test-ttc")
  end

  it "assigns every manifest row to exactly one golden tier" do
    all = JSON.parse(File.read(described_class::MANIFEST)).fetch("fonts").map { |f| f["id"] }
    expect(described_class::GOLDEN_DIRS.keys.flat_map { |t| described_class.entries(t).map { |e| e["id"] } })
      .to match_array(all)
  end

  it "gives each golden one row per face, with a basename path and no absolute path anywhere" do
    files.each do |id|
      text = File.read(described_class.golden_path(tier, id))
      doc = JSON.parse(text)
      expect(doc["rows"].map { |r| r["path"] }.uniq).to eq([doc["file"]])
      expect(text).not_to include(described_class::ROOT)
    end
  end

  it "has a row per member for every collection" do
    expected = { "fonttools-test-ttc" => 2, "fonttools-test-ttc-v2" => 2,
                 "ttc-4members-shared" => 4, "woff2-collection-4members" => 4 }
    expected.each do |id, faces|
      doc = JSON.parse(File.read(described_class.golden_path("ci", id)))
      expect(doc["rows"].map { |r| r["collection_index"] }).to eq((0...faces).to_a)
    end
  end

  it "finds no difference between the committed goldens and fresh output" do
    expect(described_class.verify(tier)).to eq([])
  end

  it "generates identical bytes twice" do
    first = described_class.generate(tier)
    second = described_class.generate(tier)
    expect(second).to eq(first)
  end

  it "does not depend on where the fonts live" do
    entry = described_class.entries("ci").find { |e| e["id"] == "fonttools-test-ttc" }
    Dir.mktmpdir("elsewhere-42") do |dir|
      FileUtils.cp(described_class.font_path(entry), dir)
      moved = Fontisan::Reference.scan([File.join(dir, entry["file"])])
      rows = moved.map { |r| r.merge("path" => File.basename(r["path"])) }
      expect(JSON.parse(File.read(described_class.golden_path("ci", entry["id"])))["rows"]).to eq(rows)
    end
  end

  it "fails when one byte of a golden changes" do
    Dir.mktmpdir("goldens") do |dir|
      FileUtils.cp_r(described_class.golden_dir("ci"), File.join(dir, "scan"))
      victim = File.join(dir, "scan", "fonttools-test-ttf.json")
      bytes = File.binread(victim)
      bytes.setbyte(bytes.index("\"schema\": 1") + 10, "2".ord)
      File.binwrite(victim, bytes)
      allow(described_class).to receive(:golden_dir).with("ci").and_return(File.join(dir, "scan"))
      allow(described_class).to receive(:golden_path).and_wrap_original do |_m, _tier, id|
        File.join(dir, "scan", "#{id}.json")
      end

      problems = described_class.verify("ci")
      expect(problems.size).to eq(1)
      expect(problems.first).to include("golden differs").and include("fonttools-test-ttf.json")
    end
  end
end
