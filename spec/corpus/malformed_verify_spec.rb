# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/corpus/generate_malformed_goldens"

# Malformed-input goldens (fontist/fontisan#156, card 0e). Needs the committed
# corpus/derived malformed files only (no network).
RSpec.describe MalformedGoldens do # rubocop:disable RSpec/SpecFilePathFormat
  let(:entries) { described_class.entries }
  let(:kinds) do
    %w[truncated-10 truncated-100 truncated-half garbage empty bad-table-offset bad-checksum bad-num-tables]
  end

  def golden_for(entry)
    JSON.parse(File.read(described_class.golden_path(entry)))
  end

  it "covers all eight malformed kinds" do
    expect(entries.map { |e| e["malformed_kind"] }).to match_array(kinds)
  end

  it "matches the committed goldens" do
    expect(described_class.verify).to eq([])
  end

  it "records every kind x op in all four mode/lazy combinations" do
    entries.each do |e|
      g = golden_for(e)
      expect(g["combos"].keys).to match_array(%w[metadata/lazy=true metadata/lazy=false
                                                 full/lazy=true full/lazy=false])
      g["combos"].each do |name, c|
        want = %w[load name table_head read]
        want << "table_cmap" if name.start_with?("full")
        expect(c["ops"].keys).to match_array(want)
        c["ops"].each_value { |op| expect(op["outcome"]).to match(/\A(ok|error|skipped)\z/) }
      end
      expect(g["audit"]["outcome"]).to match(/\A(ok|error)\z/)
      expect(g["scan"]["outcome"]).to eq("ok")
    end
  end

  it "pins the lazy-failure reference behaviour" do
    by_kind = entries.to_h { |e| [e["malformed_kind"], golden_for(e)] }
    point = ->(k, c = "full/lazy=true") { by_kind[k]["combos"][c]["failure_point"] }
    expect(point.call("truncated-10")).to eq("load")
    expect(point.call("garbage")).to eq("load")
    expect(point.call("truncated-half")).to eq("name")
    expect(point.call("bad-checksum")).to be_nil
    expect(by_kind["garbage"]["combos"]["full/lazy=true"]["ops"]["load"]["error_class"])
      .to eq("Fontisan::InvalidFontError")
    expect(by_kind["truncated-10"]["combos"]["full/lazy=true"]["ops"]["load"]["message"])
      .to eq("Invalid TrueTypeFont file: End of file reached")
  end

  it "fails verify when one outcome is flipped" do
    Dir.mktmpdir do |dir|
      entries.each { |e| FileUtils.cp(described_class.golden_path(e), dir) }
      target = File.join(dir, "malformed-truncated-half.json")
      data = JSON.parse(File.read(target))
      data["combos"]["full/lazy=true"]["ops"]["name"]["outcome"] = "ok"
      File.write(target, JSON.pretty_generate(data))
      allow(described_class).to receive(:golden_path) { |e| File.join(dir, "#{e['id']}.json") }
      problems = described_class.verify
      expect(problems).to eq(["malformed-truncated-half: golden differs from current behaviour"])
    end
  end

  it "is deterministic across two generations" do
    first = entries.map { |e| described_class.render(e) }
    second = entries.map { |e| described_class.render(e) }
    expect(first).to eq(second)
  end

  it "does not depend on where the fonts live" do
    Dir.mktmpdir("elsewhere-42") do |dir|
      entries.each do |e|
        FileUtils.cp(File.join(described_class::DERIVED_DIR, e["file"]), dir)
        expect(described_class.render(e, dir: dir)).to eq(File.read(described_class.golden_path(e)))
      end
    end
  end

  describe ".normalize_message" do
    it "masks paths, hex and numbers but keeps words" do
      msg = "bad /tmp/x-1/f.ttf at 0xBEEF, offset 12 (OS/2, TTC/OTC/dfont) a/b.otf"
      expect(described_class.normalize_message(msg))
        .to eq("bad <PATH> at <HEX>, offset <N> (OS/<N>, TTC/OTC/dfont) <PATH>")
    end
  end
end
