# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../../scripts/corpus/generate_convert_goldens"

# Convert goldens (fontist/fontisan#156, card 0c). Needs `rake corpus:fetch`
# (the corpus fonts), `opentype-sanitizer` (OTS_PYTHON=<python with it>) and
# the pinned woff2_decompress; a missing tool fails the examples, never skips
# them. Run with `bundle exec rspec --options /dev/null spec/corpus/...`.
module ConvertSpecCache
  module_function

  def tiers
    %w[ci]
  end

  # Generated twice, in one process, once per run of the suite.
  def runs
    @runs ||= [ConvertGoldens.generate(tiers), ConvertGoldens.generate(tiers)]
  end
end

RSpec.describe ConvertGoldens do
  let(:tiers) { ConvertSpecCache.tiers }
  let(:goldens) do
    Dir.glob(File.join(described_class::GOLDEN_DIR, "*.json")).to_h { |f| [File.basename(f, ".json"), JSON.parse(File.read(f))] }
  end

  describe "completeness" do
    it "has a golden for every corpus font that converts, and nothing else" do
      expect(goldens.keys.sort).to eq(described_class.expected_keys(tiers).keys.sort)
    end

    it "has a result for every format pair, collection member, named instance and subset case" do
      described_class.expected_keys(tiers).each do |id, keys|
        expect(goldens.fetch(id)["cases"].keys.sort).to eq(keys.sort), "#{id}: case keys differ"
      end
    end

    it "covers the four fontist ops on at least one font each" do
      ops = goldens.values.flat_map { |g| g["cases"].values.map { |c| c.dig("params", "op") } }.uniq
      expect(ops).to include("format", "extract", "instance", "subset")
    end

    it "covers both subset request kinds and every named instance of the variable fonts" do
      subset = goldens.values.flat_map { |g| g["cases"].select { |k, _| k.start_with?("subset:") }.values }
      expect(subset.map { |c| c["params"].keys.grep(/text|unicodes/) }.flatten.uniq).to contain_exactly("text", "unicodes")
      fvar_faces = goldens["source-sans-3-vf-upright-ttf"]["cases"].keys.grep(/\Ainstance:/)
      expect(fvar_faces.size).to eq(7)
    end
  end

  describe "shape" do
    it "states the comparison class and stores only hashes" do
      goldens.each do |id, g|
        g["cases"].each do |key, c|
          expect(c["class"]).to eq(key.match?(/\Aformat:woff2?\z/) ? "decoded-exact" : "exact"), "#{id}/#{key}"
          next unless c["outcome"] == "ok"

          expect(c["output"]["sha256"]).to match(/\A\h{64}\z/)
          expect(c).to include("decoded_tables") if c["class"] == "decoded-exact"
          expect(c).not_to include("decoded_tables") if c["class"] == "exact"
        end
      end
    end
  end

  describe "independent validator" do
    let(:failures) { described_class.ots_failures }

    it "passes OTS for every output, or logs an OTS exception in corpus/TRIAGE_CONVERT.md" do
      unlisted = failures - described_class.listed_exceptions
      expect(unlisted).to be_empty, "OTS failures not listed in corpus/TRIAGE_CONVERT.md:\n  #{unlisted.join("\n  ")}"
    end

    it "lists no exception that no longer fails OTS" do
      expect(described_class.listed_exceptions - failures).to be_empty
    end

    it "marks every OTS failure as a known_reference_bug in the golden" do
      goldens.each_value do |g|
        g["cases"].each_value do |c|
          expect(c["known_reference_bug"]).to be_a(String) if c.dig("ots", "verdict") == "fail"
          expect(c).not_to include("known_reference_bug") unless c.dig("ots", "verdict") == "fail"
        end
      end
    end
  end

  describe "regeneration" do
    it "is deterministic: two generations are byte-identical" do
      first, second = ConvertSpecCache.runs
      expect(second).to eq(first)
    end

    it "matches the committed goldens byte for byte" do
      first, = ConvertSpecCache.runs
      first.each do |name, text|
        golden = File.read(File.join(described_class::GOLDEN_DIR, name))
        expect(described_class.same_golden?(golden, text)).to be(true), "#{name} differs from its golden"
      end
    end
  end

  describe "a deliberately broken op" do
    let(:id) { "fonttools-test-ttf" }

    it "fails verify when convert emits different bytes" do
      allow(Fontisan::Reference).to receive(:convert).and_wrap_original do |orig, *args, **kw|
        orig.call(*args, **kw).tap { File.open(kw.fetch(:output), "ab") { |f| f.write("\x00") } }
      end
      problems = described_class.verify(tiers, only: [id])
      expect(problems.join).to include("#{id}.json", "format:otf", "format:woff", "format:woff2")
    end

    it "fails verify when a golden byte changes" do
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(described_class::GOLDEN_DIR, "#{id}.json"), dir)
        file = File.join(dir, "#{id}.json")
        File.write(file, File.read(file).sub(/"sha256": "(\h)/) { "\"sha256\": \"#{Regexp.last_match(1) == '0' ? '1' : '0'}" })
        expect(described_class.verify(tiers, only: [id], dir: dir)).not_to be_empty
      end
    end

    it "passes verify on the untouched golden" do
      expect(described_class.verify(tiers, only: [id])).to be_empty
    end
  end
end
