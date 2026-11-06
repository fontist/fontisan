# frozen_string_literal: true

require "tmpdir"
require_relative "support/corpus_paths"
require_relative "../../corpus/derive/sfnt"

# Reference bugs found by the table-drop sweep (fontisan#156). Each example
# derives a copy of a corpus font with one table removed.
RSpec.describe "table-drop sweep reference fixes" do
  def without_table(id, *tags)
    version, tables = CorpusSfnt.parse(File.binread(CorpusPaths.path(id)))
    path = File.join(Dir.mktmpdir, "dropped-#{id}.ttf")
    File.binwrite(path, CorpusSfnt.build(version, tables.to_h.except(*tags).to_a))
    path
  end

  def convert(path, target)
    out = File.join(Dir.mktmpdir, "out.#{target}")
    Fontisan::Reference.convert(path, to: target, output: out, timestamp: 1_735_689_600)
    out
  end

  describe Fontisan::Audit::Checks::MaxpCheck do
    it "reports the CFF-style version warning for a font whose glyf table is gone" do
      font = Fontisan::FontLoader.load(without_table("fonttools-test-ttf", "glyf"))

      issues = described_class.call(font)

      expect(issues.map { |i| [i.severity, i.location, i.message] }).to eq(
        [["warning", "maxp.version",
          "maxp.version is 0x10000 but should be 0.5 (0x5000) for CFF-based fonts"]],
      )
    end
  end

  describe Fontisan::Variation::Instancing::TrueTypeInstancer do
    let(:vf) { CorpusSfnt.parse(File.binread(CorpusPaths.path("source-sans-3-vf-upright-ttf"))) }
    let(:tables) { vf.last.to_h }

    %w[head hhea hmtx maxp loca].each do |tag|
      it "raises a missing-table error naming #{tag} instead of a NoMethodError" do
        expect { described_class.new(tables.except(tag), {}) }
          .to raise_error(Fontisan::MissingTableError,
                          "Font missing required #{tag} table")
      end
    end
  end

  describe "convert of a variable font with fvar dropped" do
    it "converts glyf larger than the short-loca limit to woff2" do
      out = convert(without_table("source-sans-3-vf-upright-ttf", "fvar"), :woff2)

      expect(File.binread(out, 4)).to eq("wOF2")
    end
  end

  describe "convert of a font with no name table" do
    it "reports the missing table instead of a BINARY encoding error" do
      expect { convert(without_table("names-mac-roman-only", "name"), :otf) }
        .to raise_error(Fontisan::Error) { |e|
          expect(e.message).to include("Required table 'name' is missing")
          expect(e.message).not_to include("BINARY")
        }
    end
  end

  describe "convert of a font with no cmap table" do
    it "reports the missing table without a leaked NoMethodError" do
      expect { convert(without_table("names-mac-roman-only", "cmap"), :otf) }
        .to raise_error(Fontisan::Error) { |e|
          expect(e.message).to include("Required table 'cmap' is missing")
          expect(e.message).not_to include("NoMethodError")
        }
    end
  end
end
