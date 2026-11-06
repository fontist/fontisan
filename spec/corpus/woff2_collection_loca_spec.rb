# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "support/corpus_paths"
require_relative "../../corpus/derive/sfnt"

# fontisan#156: a collection member whose glyf, padded to 4 bytes per glyph
# by the WOFF2 decoder, outgrows what a short loca can index must be written
# with a long loca (the single-font encoder already does this).
RSpec.describe Fontisan::Woff2::CollectionEncoder do
  let(:dir) { Dir.mktmpdir }
  let(:font) do
    version, tables = CorpusSfnt.parse(File.binread(CorpusPaths.path("source-sans-3-vf-upright-ttf")))
    path = File.join(dir, "member.ttf")
    kept = tables.to_h.except(*%w[fvar gvar avar HVAR MVAR STAT cvar GDEF])
    File.binwrite(path, CorpusSfnt.build(version, kept.to_a))
    Fontisan::FontLoader.load(path)
  end
  let(:woff2) do
    described_class.new(timestamp: 1_735_689_600).encode_fonts([font, font])
  end

  it "uses a member that is short-loca but whose 4-byte padded glyf overflows it" do
    expect(font.table("head").index_to_loc_format).to eq(0)
    padded_max = font.table_data["glyf"].bytesize + (3 * font.table("maxp").num_glyphs)
    expect(padded_max).to be > 0x1FFFE
  end

  def decompress(bytes)
    exe = File.join(CorpusPaths::ROOT, "corpus/fonts/.tools/woff2/bin/woff2_decompress")
    skip "pinned woff2_decompress not built (scripts/build-woff2.sh)" unless File.executable?(exe)
    input = File.join(dir, "in.woff2")
    File.binwrite(input, bytes)
    _out, err, status = Open3.capture3(exe, input)
    expect(status).to be_success, err
    File.binread(File.join(dir, "in.ttf"))
  end

  it "decodes with the pinned reference decoder to a monotonic long loca" do
    ttc = decompress(woff2)
    offset = ttc.unpack1("@12N")
    tables = {}
    ttc.unpack1("@#{offset + 4}n").times do |i|
      tag, _sum, off, len = ttc.unpack("@#{offset + 12 + 16 * i}a4NNN")
      tables[tag] = ttc.byteslice(off, len)
    end
    loca = tables["loca"].unpack("N*")

    expect(tables["head"].unpack1("@50n")).to eq(1)
    expect(loca.each_cons(2).all? { |a, b| a <= b }).to be(true)
    expect(loca.last).to eq(tables["glyf"].bytesize)
  end

  it "decodes to a file OTS sanitizes" do
    ots_python = ENV["OTS_PYTHON"]
    skip "OTS_PYTHON not set" unless ots_python && File.executable?(ots_python)
    path = File.join(dir, "out.ttc")
    File.binwrite(path, decompress(woff2))

    _out, err, status = Open3.capture3(ots_python, "-m", "ots", path)
    expect(status).to be_success, err
  end

  it "records the long format in the decoded member's head" do
    path = File.join(dir, "c.woff2")
    File.binwrite(path, woff2)
    font = Fontisan::Woff2Collection.from_file(path).extract_fonts.first

    expect(font.table("head").index_to_loc_format).to eq(1)
  end
end
