# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Fontisan::FontLoader, ".detect_format" do
  let(:ttf_fixture)   { File.join(FIXTURES_DIR, "fonttools", "TestTTF.ttf") }
  let(:otf_fixture)   { File.join(FIXTURES_DIR, "fonttools", "TestOTF.otf") }
  let(:ttc_fixture)   { File.join(FIXTURES_DIR, "fonttools", "TestTTC.ttc") }
  let(:woff_fixture)  { File.join(FIXTURES_DIR, "fonttools", "TestWOFF.woff") }
  let(:woff2_fixture) do
    File.join(FIXTURES_DIR, "fonttools", "TestWOFF2.woff2")
  end
  let(:dfont_fixture) do
    File.join(FIXTURES_DIR, "fonttools", "TestDFONT.dfont")
  end
  let(:pfb_fixture) do
    File.join(FIXTURES_DIR, "fonts", "type1", "quicksand.pfb")
  end
  let(:otc_fixture) do
    File.join(FIXTURES_DIR, "fonts", "NotoSerifCJK-VF", "Variable", "OTC",
              "NotoSerifCJK-VF.otf.ttc")
  end

  it "recognises a TrueType font by its 0x00010000 magic" do
    expect(described_class.detect_format(ttf_fixture)).to eq(:ttf)
  end

  it "recognises an Apple-style 'true' TrueType signature" do
    Tempfile.create(["legacy-mac", ".bin"]) do |f|
      f.binmode
      # 'true' magic plus a minimal-but-believable SFNT table directory header
      f.write("true\x00\x00\x00\x00")
      f.write("\x00" * 8)
      f.flush
      expect(described_class.detect_format(f.path)).to eq(:ttf)
    end
  end

  it "recognises an OpenType-CFF font by its 'OTTO' magic" do
    expect(described_class.detect_format(otf_fixture)).to eq(:otf)
  end

  it "recognises a TrueType Collection (all inner fonts are TrueType)" do
    expect(described_class.detect_format(ttc_fixture)).to eq(:ttc)
  end

  it "recognises an OpenType Collection by scanning inner fonts" do
    skip "OTC fixture not downloaded" unless File.exist?(otc_fixture)
    expect(described_class.detect_format(otc_fixture)).to eq(:otc)
  end

  it "reports NotoSerifCJK.ttc as :otc despite its .ttc extension (it contains CFF fonts)" do
    noto = File.join(FIXTURES_DIR, "fonts", "NotoSerifCJK", "NotoSerifCJK.ttc")
    skip "NotoSerifCJK fixture not downloaded" unless File.exist?(noto)
    expect(described_class.detect_format(noto)).to eq(:otc)
  end

  it "recognises a WOFF font by its 'wOFF' magic" do
    expect(described_class.detect_format(woff_fixture)).to eq(:woff)
  end

  it "recognises a WOFF2 font by its 'wOF2' magic" do
    expect(described_class.detect_format(woff2_fixture)).to eq(:woff2)
  end

  it "recognises a dfont resource fork" do
    expect(described_class.detect_format(dfont_fixture)).to eq(:dfont)
  end

  it "recognises a PFB Type 1 font by its 0x80 0x01 marker" do
    expect(described_class.detect_format(pfb_fixture)).to eq(:pfb)
  end

  it "recognises a PFA Type 1 font by its Adobe header" do
    Tempfile.create(["adobe", ".pfa"]) do |f|
      f.binmode
      f.write("%!PS-AdobeFont-1.0: TestFont 001.000\n12 dict begin\n")
      f.flush
      expect(described_class.detect_format(f.path)).to eq(:pfa)
    end
  end

  it "recognises a PFA whose Adobe header is preceded by whitespace" do
    Tempfile.create(["whitespace", ".pfa"]) do |f|
      f.binmode
      f.write("\n\n  %!PS-AdobeFont-1.0: TestFont 001.000\n")
      f.flush
      expect(described_class.detect_format(f.path)).to eq(:pfa)
    end
  end

  it "raises Errno::ENOENT when the file is missing" do
    expect { described_class.detect_format("/no/such/file.ttf") }
      .to raise_error(Errno::ENOENT)
  end

  it "returns nil for an unrecognised binary" do
    Tempfile.create(["junk", ".bin"]) do |f|
      f.binmode
      f.write("ZZZZ-this-is-not-a-font")
      f.flush
      expect(described_class.detect_format(f.path)).to be_nil
    end
  end

  it "returns nil for an empty file" do
    Tempfile.create(["empty", ".ttf"]) do |f|
      expect(described_class.detect_format(f.path)).to be_nil
    end
  end

  it "returns nil for a 1-byte file (below the PFB marker threshold)" do
    Tempfile.create(["tiny", ".bin"]) do |f|
      f.binmode
      f.write("\x80")
      f.flush
      expect(described_class.detect_format(f.path)).to be_nil
    end
  end

  it "returns nil for a 2-byte file whose bytes don't form a PFB marker" do
    Tempfile.create(["tiny", ".bin"]) do |f|
      f.binmode
      f.write("ab")
      f.flush
      expect(described_class.detect_format(f.path)).to be_nil
    end
  end

  it "returns nil for a 3-byte file (below the SFNT signature threshold)" do
    Tempfile.create(["tiny", ".bin"]) do |f|
      f.binmode
      f.write("abc")
      f.flush
      expect(described_class.detect_format(f.path)).to be_nil
    end
  end

  it "returns nil for a PostScript EPSF that uses the .pfa extension but lacks the Adobe Type 1 header" do
    Tempfile.create(["epsf", ".pfa"]) do |f|
      f.binmode
      f.write("%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 0 0 100 100\n")
      f.flush
      expect(described_class.detect_format(f.path)).to be_nil
    end
  end

  it "does not match a file that mentions the PFA signature only in a comment partway in" do
    Tempfile.create(["fake", ".bin"]) do |f|
      f.binmode
      f.write("%!PS-Adobe-3.0 EPSF-3.0\n% see %!PS-AdobeFont-1.0 for details\n")
      f.flush
      expect(described_class.detect_format(f.path)).to be_nil
    end
  end

  it "raises a system error when given a directory path" do
    Dir.mktmpdir do |dir|
      expect do
        described_class.detect_format(dir)
      end.to raise_error(SystemCallError)
    end
  end

  context "when a file's extension lies about its content" do
    # Regression: macOS ships a single OpenType-CFF font as
    # SauberScript.ttc inside the FontServices private framework. The
    # extension says collection, the bytes say single font.
    it "reports the on-disk format, not the extension (OTF mislabeled as .ttc)" do
      Dir.mktmpdir do |dir|
        masquerading = File.join(dir, "PretendCollection.ttc")
        FileUtils.cp(otf_fixture, masquerading)
        expect(described_class.detect_format(masquerading)).to eq(:otf)
      end
    end

    it "reports a real collection as :ttc even when extension is .otf" do
      Dir.mktmpdir do |dir|
        masquerading = File.join(dir, "PretendSingle.otf")
        FileUtils.cp(ttc_fixture, masquerading)
        expect(described_class.detect_format(masquerading)).to eq(:ttc)
      end
    end

    # Regression: detect_format previously delegated Type 1 detection to a
    # helper that returned true based on extension alone, so an SFNT renamed
    # to .pfa/.pfb/.ps was misreported as Type 1 and would be sent down the
    # Type 1 parser path.
    it "reports an OTF renamed to .pfa as :otf" do
      Dir.mktmpdir do |dir|
        masquerading = File.join(dir, "fake.pfa")
        FileUtils.cp(otf_fixture, masquerading)
        expect(described_class.detect_format(masquerading)).to eq(:otf)
      end
    end

    it "reports a TTF renamed to .pfb as :ttf" do
      Dir.mktmpdir do |dir|
        masquerading = File.join(dir, "fake.pfb")
        FileUtils.cp(ttf_fixture, masquerading)
        expect(described_class.detect_format(masquerading)).to eq(:ttf)
      end
    end

    it "reports a WOFF renamed to .ps as :woff" do
      Dir.mktmpdir do |dir|
        masquerading = File.join(dir, "fake.ps")
        FileUtils.cp(woff_fixture, masquerading)
        expect(described_class.detect_format(masquerading)).to eq(:woff)
      end
    end

    it "reports a PFB renamed to .otf as :pfb" do
      Dir.mktmpdir do |dir|
        masquerading = File.join(dir, "fake.otf")
        FileUtils.cp(pfb_fixture, masquerading)
        expect(described_class.detect_format(masquerading)).to eq(:pfb)
      end
    end
  end
end
