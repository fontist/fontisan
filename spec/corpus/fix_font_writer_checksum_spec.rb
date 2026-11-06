# frozen_string_literal: true

require_relative "support/corpus_paths"
require "tmpdir"

RSpec.describe Fontisan::FontWriter do
  # Source Sans 3 carries a non-zero head.checkSumAdjustment, which the old
  # directory checksum for `head` included.
  it "is idempotent: write, reload, write gives the same bytes" do
    source = Fontisan::FontLoader.load(CorpusPaths.path("source-sans-3-regular-ttf"))
    first = described_class.write_font(source.table_data)

    Dir.mktmpdir do |dir|
      file = File.join(dir, "first.ttf")
      File.binwrite(file, first)
      second = described_class.write_font(Fontisan::FontLoader.load(file).table_data)

      expect(second).to eq(first)
    end
  end

  it "stores the head directory checksum with checkSumAdjustment zeroed" do
    source = Fontisan::FontLoader.load(CorpusPaths.path("source-sans-3-regular-ttf"))
    bytes = described_class.write_font(source.table_data)
    head = source.table_data["head"]
    zeroed = head.b.dup.tap { |h| h[8, 4] = "\0\0\0\0" }
    entry_checksum = bytes.byteslice(12, 16 * bytes.byteslice(4, 2).unpack1("n"))
      .scan(/.{16}/m).find { |e| e.start_with?("head") }.byteslice(4, 4).unpack1("N")
    expected = zeroed.ljust((zeroed.bytesize + 3) / 4 * 4, "\0").unpack("N*").sum & 0xFFFFFFFF

    expect(entry_checksum).to eq(expected)
  end
end
