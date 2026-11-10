# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "timeout"
require "tmpdir"

# A ttcf header declaring 0xFFFFFFFF fonts used to make BinData read a 4 GiB
# offset table eagerly: detect/load/scan/info never returned. The header is now
# refused when its offset table cannot fit in the file, exactly like any other
# truncated header (detect_format nil, InvalidFontError on load).
RSpec.describe "TTC header with a huge num_fonts" do
  let(:header) { "ttcf\x00\x01\x00\x00\xFF\xFF\xFF\xFF".b }
  let(:dir) { Dir.mktmpdir("ttc-huge") }
  let!(:path) { File.join(dir, "huge.ttc").tap { |p| File.binwrite(p, header) } }

  after { FileUtils.remove_entry(dir) }

  def fast(&)
    Timeout.timeout(5, &)
  end

  it "detect_format returns nil without hanging" do
    expect(fast { Fontisan::FontLoader.detect_format(path) }).to be_nil
  end

  it "load raises InvalidFontError without hanging" do
    expect { fast { Fontisan::FontLoader.load(path) } }
      .to raise_error(Fontisan::InvalidFontError, /Unknown font format/)
  end

  it "load_collection raises InvalidFontError without hanging" do
    expect { fast { Fontisan::FontLoader.load_collection(path) } }
      .to raise_error(Fontisan::InvalidFontError)
  end

  it "info raises InvalidFontError without hanging" do
    expect { fast { Fontisan.info(path) } }
      .to raise_error(Fontisan::InvalidFontError)
  end

  it "scan returns a row carrying the collection error without hanging" do
    rows = fast { Fontisan.scan([path]) }
    expect(rows.size).to eq(1)
    expect(rows.first["errors"]).not_to be_empty
  end

  it "audit_dir reports the file as an error entry without hanging" do
    entries = fast { Fontisan::Engine.audit_dir(dir) }
    expect(entries.map { |e| e["path"] }).to eq(["huge.ttc"])
    expect(entries.first["error"]["class"]).to eq("Fontisan::InvalidFontError")
  end

  it "BaseCollection.read raises ValidityError naming the declared count" do
    expect { Fontisan::TrueTypeCollection.read(StringIO.new(header)) }
      .to raise_error(BinData::ValidityError, /4294967295 fonts declared/)
  end

  it "still reads a collection whose offset table exactly fits" do
    io = StringIO.new("ttcf\x00\x01\x00\x00\x00\x00\x00\x01\x00\x00\x00\x10".b)
    expect(Fontisan::TrueTypeCollection.read(io).font_offsets.to_a).to eq([16])
  end
end
