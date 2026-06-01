# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Fontisan::FontLoader, ".detect_format" do
  let(:ttf_fixture) { File.join(FIXTURES_DIR, "fonttools", "TestTTF.ttf") }
  let(:otf_fixture) { File.join(FIXTURES_DIR, "fonttools", "TestOTF.otf") }
  let(:ttc_fixture) { File.join(FIXTURES_DIR, "fonttools", "TestTTC.ttc") }

  it "recognises a TrueType font by its 0x00010000 magic" do
    expect(described_class.detect_format(ttf_fixture)).to eq(:ttf)
  end

  it "recognises an OpenType-CFF font by its 'OTTO' magic" do
    expect(described_class.detect_format(otf_fixture)).to eq(:otf)
  end

  it "recognises a TrueType Collection by its 'ttcf' magic" do
    expect(described_class.detect_format(ttc_fixture)).to eq(:ttc)
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
  end
end
