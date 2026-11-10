# frozen_string_literal: true

require "spec_helper"
require "digest"
require "json"
require "tmpdir"

RSpec.describe Fontisan::Reference do
  include TierParity

  let(:dir) { File.expand_path("../fixtures/fonttools", __dir__) }
  let(:ttf) { File.join(dir, "TestTTF.ttf") }
  let(:otf) { File.join(dir, "TestOTF.otf") }
  let(:ttc) { File.join(dir, "TestTTC.ttc") }
  let(:woff) { File.join(dir, "TestWOFF.woff") }
  let(:vf) do
    File.expand_path("../fixtures/fonts/MonaSansVF/MonaSansVF[wght,opsz].ttf",
                     __dir__)
  end
  let(:out) { Dir.mktmpdir("reference-spec") }
  let(:mac_epoch_offset) { Fontisan::Tables::Head::MAC_EPOCH_OFFSET }
  let(:stamp) { 1_700_000_000 }

  after { FileUtils.rm_rf(out) }

  # Run the block once per fixed wall clock and return the results (binary
  # results as their SHA-256, so failures stay printable).
  def under_two_clocks
    [Time.at(1_000_000_000), Time.at(1_900_000_000)].map do |clock|
      allow(Time).to receive(:now).and_return(clock)
      result = yield
      result.is_a?(String) && result.encoding == Encoding::BINARY ? Digest::SHA256.hexdigest(result) : result
    end
  end

  def head_modified(path)
    font = Fontisan::FontLoader.load(path, mode: :full)
    font.table("head").modified_raw - mac_epoch_offset
  end

  describe ".read" do
    it "returns one face per collection member" do
      expect(described_class.read(ttc, mode: :full, lazy: false).map { |f| f["index"] })
        .to eq([0, 1])
    end

    it "digests every table in full mode" do
      face = described_class.read(ttf, mode: :full, lazy: false).first
      glyf = Digest::SHA256.hexdigest(Fontisan::FontLoader.load(ttf).table_data["glyf"])
      expect(face["tables"].find { |t| t["tag"] == "glyf" }["sha256"]).to eq(glyf)
    end

    it "leaves tables the metadata mode gates out undigested" do
      tables = described_class.read(ttf, mode: :metadata, lazy: true).first["tables"]
      expect(tables.find { |t| t["tag"] == "glyf" }["sha256"]).to be_nil
    end

    it "reports the name records with decoded strings" do
      names = described_class.read(ttf).first["names"]
      expect(names).to include(a_hash_including("name_id" => 1,
                                                "string" => "Test TTF"))
    end

    it "gives the cmap count and a digest of the sorted codepoints" do
      cmap = described_class.read(ttf, mode: :full, lazy: false).first["cmap"]
      expect(cmap["count"]).to eq(5)
      expect(cmap["sha256"]).to match(/\A\h{64}\z/)
    end

    it "gives raw integers for the variable axes and instances" do
      fvar = described_class.read(vf, mode: :full, lazy: false).first["fvar"]
      expect(fvar["axes"].first).to include("axis_tag" => "wght",
                                            "min_value_raw" => 200 * 65_536)
      expect(fvar["instances"].first["coordinates_raw"]).to all(be_an(Integer))
    end

    it "hashes glyf outlines as the byte range loca gives (independent loca read)" do
      raw = Fontisan::FontLoader.load(ttf).table_data
      offsets = raw["loca"].unpack("n*").map { |o| o * 2 } # head says short loca
      expect(Fontisan::Tables::Head.read(raw["head"]).index_to_loc_format).to eq(0)
      expected = offsets.each_cons(2).map do |a, b|
        Digest::SHA256.hexdigest(raw["glyf"].byteslice(a, b - a))
      end
      expect(described_class.outline_hashes(ttf)).to eq("kind" => "glyf",
                                                        "hashes" => expected)
    end

    describe "hmtx_metrics (decoded metrics, not raw bytes)" do
      def metrics(path = ttf)
        described_class.read(path, mode: :full, lazy: false).first["hmtx_metrics"]
      end

      it "digests the metrics of every glyph" do
        expect(metrics).to include("count" => Fontisan::FontLoader.load(ttf, mode: :full).table("maxp").num_glyphs,
                                   "sha256" => match(/\A\h{64}\z/))
      end

      it "is gated out in metadata mode, like the table it digests" do
        expect(described_class.read(ttf, mode: :metadata).first["hmtx_metrics"]).to be_nil
      end

      # Stubs the Ruby hmtx decoder, so it only means something on the ruby tier.
      it "changes when the hmtx decoder returns a different advance (a raw-byte digest would not)" do
        with_engine("ruby") do
          before = metrics["sha256"]
          allow_any_instance_of(Fontisan::Tables::Hmtx).to receive(:metric_for).and_wrap_original do |orig, gid| # rubocop:disable RSpec/AnyInstance
            orig.call(gid)&.merge(advance_width: orig.call(gid)[:advance_width] + 1)
          end
          expect(metrics["sha256"]).not_to eq(before)
        end
      end
    end

    it "hashes CFF CharStrings, also for the same font inside WOFF" do
      from_otf = described_class.outline_hashes(otf)
      expect(from_otf["kind"]).to eq("cff")
      expect(from_otf["hashes"].size).to eq(6)
      expect(described_class.outline_hashes(woff)).to eq(from_otf)
    end

    it "contains no Float and no clock value" do
      data = described_class.read(vf, mode: :full, lazy: false)
      expect(JSON.parse(described_class.canonical_json(data))).to eq(data)
      expect { described_class.normalize("x" => 1.5) }
        .to raise_error(ArgumentError, /Float/)
    end

    it "rejects a loaded font object" do
      font = Fontisan::FontLoader.load(ttf)
      expect { described_class.read(font) }.to raise_error(TypeError, /file path/)
    end

    it "raises the loader's error for a missing file" do
      expect { described_class.read(File.join(out, "none.ttf")) }
        .to raise_error(Errno::ENOENT)
    end
  end

  describe ".audit" do
    it "drops the clock and version fields" do
      report = described_class.audit(ttf, validate: true).first
      expect(report.keys).not_to include("generated_at", "fontisan_version")
      expect(report["validation_summary"]).to include("total")
    end

    it "is byte-identical across runs and clocks" do
      runs = under_two_clocks do
        described_class.canonical_json(described_class.audit(ttf, validate: true))
      end
      expect(runs.uniq.size).to eq(1)
    end

    it "gives one report per collection face" do
      expect(described_class.audit(ttc).map { |r| r["font_index"] }).to eq([0, 1])
    end

    it "stores Fixed values as raw integers" do
      report = described_class.audit(vf).first
      expect(report["axes"].first).to include("min_value_raw" => 200 * 65_536)
      expect(report).to include("font_revision_raw" => 131_596)
    end
  end

  describe ".audit_dir" do
    it "audits every font under the directory, sorted, recording failures" do
      FileUtils.mkdir_p(File.join(out, "sub"))
      FileUtils.cp(ttf, File.join(out, "sub", "b.ttf"))
      FileUtils.cp(otf, File.join(out, "a.otf"))
      File.binwrite(File.join(out, "c.ttf"), "not a font at all")
      File.write(File.join(out, "readme.txt"), "x")

      entries = described_class.audit_dir(out)

      expect(entries.map { |e| e["path"] }).to eq(%w[a.otf c.ttf sub/b.ttf])
      expect(entries[1]["error"]["class"]).to eq("Fontisan::InvalidFontError")
      expect(entries[0]["faces"].first["source_file"]).to eq("a.otf")
    end
  end

  describe ".convert" do
    it "writes the output without printing" do
      target = File.join(out, "o.otf")
      expect { described_class.convert(ttf, to: :otf, output: target) }
        .not_to output.to_stdout
      expect(File.binread(target, 4)).to eq("OTTO")
    end

    it "ignores timestamp for targets that do not stamp" do
      first, second = under_two_clocks do
        target = File.join(out, "o.woff")
        described_class.convert(ttf, to: :woff, output: target, timestamp: stamp)
        File.binread(target)
      end
      expect(first).to eq(second)
    end

    it "keeps the clock behaviour of WOFF2 when timestamp is nil" do
      first, second = under_two_clocks do
        target = File.join(out, "o.woff2")
        described_class.convert(ttf, to: :woff2, output: target)
        File.binread(target)
      end
      expect(first).not_to eq(second)
    end

    it "fixes WOFF2 bytes and head.modified when timestamp is given" do
      first, second = under_two_clocks do
        target = File.join(out, "o.woff2")
        described_class.convert(ttf, to: :woff2, output: target, timestamp: stamp)
        File.binread(target)
      end
      expect(first).to eq(second)
      expect(head_modified(File.join(out, "o.woff2"))).to eq(stamp)
    end

    it "accepts a Time for timestamp" do
      target = File.join(out, "t.woff2")
      described_class.convert(ttf, to: :woff2, output: target, timestamp: Time.at(stamp))
      expect(head_modified(target)).to eq(stamp)
    end

    it "fixes WOFF2 collection bytes when timestamp is given" do
      first, second = under_two_clocks do
        target = File.join(out, "c.woff2")
        described_class.convert(ttc, to: :woff2, output: target, timestamp: stamp)
        File.binread(target)
      end
      expect(first).to eq(second)
    end

    it "converts TTF/OTF/WOFF identically under two clocks" do
      %i[otf woff].each do |format|
        first, second = under_two_clocks do
          target = File.join(out, "o.#{format}")
          described_class.convert(ttf, to: format, output: target)
          File.binread(target)
        end
        expect(first).to eq(second), "#{format} differs between clocks"
      end
    end
  end

  describe ".extract" do
    it "returns the path of the extracted member" do
      path = described_class.extract(ttc, index: 1, output_dir: out)
      expect(File.dirname(path)).to eq(out)
      expect(Fontisan::FontLoader.load(path).table("name").english_name(1))
        .to eq("Test TTF")
    end
  end

  describe ".instance" do
    it "returns a static font, identical under two clocks" do
      first, second = under_two_clocks do
        described_class.instance(vf, coords: { "wght" => 400, "opsz" => 14 })
      end
      expect(first).to eq(second)
      File.binwrite(File.join(out, "i.ttf"),
                    described_class.instance(vf, coords: { "wght" => 400, "opsz" => 14 }))
      expect(Fontisan::FontLoader.load(File.join(out, "i.ttf")).has_table?("fvar"))
        .to be(false)
    end
  end

  describe ".subset" do
    it "keeps the glyphs of the text, identical under two clocks" do
      first, second = under_two_clocks do
        described_class.subset(ttf, text: ".")
      end
      expect(first).to eq(second)
      File.binwrite(File.join(out, "s.ttf"), described_class.subset(ttf, text: "."))
      expect(Fontisan::FontLoader.load(File.join(out, "s.ttf")).table("maxp").num_glyphs)
        .to be < Fontisan::FontLoader.load(ttf).table("maxp").num_glyphs
    end

    it "lists the glyph ids sorted and unique" do
      gids = described_class.glyph_ids(ttf, unicodes: [0x2E, 0x2E], text: ". ")
      expect(gids).to eq(gids.uniq.sort)
      expect(gids).not_to be_empty
    end

    it "raises fontist's error when no requested character exists" do
      expect { described_class.subset(ttf, unicodes: [0x1F600]) }
        .to raise_error(Fontisan::Error,
                        "None of the requested characters exist in TestTTF.ttf")
    end

    # Stubs the Ruby font object, so it only means something on the ruby tier.
    it "raises MissingTableError, not a NoMethodError, when the font has no cmap table" do
      with_engine("ruby") do
        font = Fontisan::FontLoader.load(ttf, mode: :full, lazy: false)
        allow(font).to receive(:table).and_call_original
        allow(font).to receive(:table).with("cmap").and_return(nil)
        allow(Fontisan::FontLoader).to receive(:load).and_return(font)

        expect { described_class.subset(ttf, text: "abc") }
          .to raise_error(Fontisan::MissingTableError,
                          "Required table 'cmap' not found in font")
      end
    end
  end

  describe "timestamp plumbing below the facade" do
    # StaticFontBuilder asks for `table_data(tag)`, which only the WOFF font
    # classes answer (an SfntFont's table_data takes no argument).
    let(:woff_font) { Fontisan::FontLoader.load(woff, mode: :full) }

    it "stamps head.modified from the timestamp in the WOFF2 encoder rules" do
      head = Fontisan::FontLoader.load(ttf).table_data["head"]
      tables = { "head" => head }
      Fontisan::Woff2::EncoderRules.touch_head_modified!(tables, timestamp: stamp)
      expect(Fontisan::Tables::Head.read(tables["head"]).modified_raw)
        .to eq(stamp + mac_epoch_offset)
    end

    it "stamps head.modified from the timestamp in StaticFontBuilder" do
      binary = Fontisan::Variable::StaticFontBuilder.new(woff_font)
        .build({}, {}, timestamp: stamp)
      File.binwrite(File.join(out, "b.ttf"), binary)
      expect(head_modified(File.join(out, "b.ttf"))).to eq(stamp)
    end

    it "keeps the clock in StaticFontBuilder when no timestamp is given" do
      allow(Time).to receive(:now).and_return(Time.at(stamp + 5))
      binary = Fontisan::Variable::StaticFontBuilder.new(woff_font).build
      File.binwrite(File.join(out, "c.ttf"), binary)
      expect(head_modified(File.join(out, "c.ttf"))).to eq(stamp + 5)
    end
  end
end
