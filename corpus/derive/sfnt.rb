# frozen_string_literal: true

# Minimal raw sfnt reader/writer used only by the corpus derive scripts.
# Deliberately independent of Fontisan, so a derived font is not produced by
# the engine whose behaviour it freezes.
module CorpusSfnt
  module_function

  TTC_TAG = "ttcf"

  def checksum(data)
    padded = data + ("\0" * ((4 - (data.bytesize % 4)) % 4))
    padded.unpack("N*").sum & 0xFFFFFFFF
  end

  # @return [Array(String, Array<Array(String, String)>)] sfnt tag and
  #   [[tag, data], ...] in directory order
  def parse(bytes, offset = 0)
    version, num = bytes.byteslice(offset, 6).unpack("a4n")
    tables = Array.new(num) do |i|
      tag, _sum, off, len = bytes.byteslice(offset + 12 + (i * 16), 16)
        .unpack("a4NNN")
      [tag, bytes.byteslice(off, len)]
    end
    [version, tables]
  end

  # Fonts inside a TTC, each as [version, tables].
  def parse_ttc(bytes)
    raise "not a TTC" unless bytes.byteslice(0, 4) == TTC_TAG

    count = bytes.byteslice(8, 4).unpack1("N")
    bytes.byteslice(12, count * 4).unpack("N*").map { |o| parse(bytes, o) }
  end

  def header_fields(num_tables)
    max_pow2 = 1 << Math.log2(num_tables).floor
    [max_pow2 * 16, Math.log2(max_pow2).floor, (num_tables * 16) - (max_pow2 * 16)]
  end

  # Build one sfnt. head.checkSumAdjustment is recomputed unless
  # fix_adjustment is false.
  def build(version, tables, fix_adjustment: true)
    tables = tables.sort_by(&:first).map { |t, d| [t, d.b] }
    if fix_adjustment
      tables = tables.map do |t, d|
        t == "head" && d.bytesize >= 12 ? [t, d.dup.tap { |h| h[8, 4] = [0].pack("N") }] : [t, d]
      end
    end
    n = tables.size
    sr, es, rs = header_fields([n, 1].max)
    out = [version, n, sr, es, rs].pack("a4nnnn")
    offset = 12 + (n * 16)
    body = +"".b
    tables.each do |tag, data|
      out << [tag, checksum(data), offset + body.bytesize, data.bytesize].pack("a4NNN")
      body << data << ("\0" * ((4 - (data.bytesize % 4)) % 4))
    end
    out << body
    if fix_adjustment && (idx = tables.index { |t, d| t == "head" && d.bytesize >= 12 })
      adj = (0xB1B0AFBA - checksum(out)) & 0xFFFFFFFF
      head_off = 12 + (n * 16) + tables[0...idx].sum { |_, d| (d.bytesize + 3) & ~3 }
      out[head_off + 8, 4] = [adj].pack("N")
    end
    out
  end

  # TTC v1 with identical table data shared between members.
  def build_ttc(fonts)
    count = fonts.size
    header = 12 + (count * 4)
    dirs = fonts.map { |_, tables| 12 + (tables.size * 16) }
    data_start = header + dirs.sum
    store = +"".b
    placed = {}
    place = lambda do |data|
      placed[data] ||= begin
        pos = data_start + store.bytesize
        store << data << ("\0" * ((4 - (data.bytesize % 4)) % 4))
        pos
      end
    end
    dir_bytes = []
    fonts.each do |version, tables|
      tables = tables.sort_by(&:first)
      n = tables.size
      sr, es, rs = header_fields([n, 1].max)
      d = [version, n, sr, es, rs].pack("a4nnnn")
      tables.each do |tag, data|
        d << [tag, checksum(data), place.call(data.b), data.bytesize].pack("a4NNN")
      end
      dir_bytes << d
    end
    offsets = []
    pos = header
    dir_bytes.each do |d|
      offsets << pos
      pos += d.bytesize
    end
    ([TTC_TAG, 0x00010000, count].pack("a4NN") + offsets.pack("N*") +
      dir_bytes.join + store)
  end

  # name table (format 0). records: [[platform, encoding, language, name_id,
  # bytes], ...]
  def name_table(records)
    records = records.sort_by { |r| r[0..3] }
    strings = +"".b
    recs = records.map do |pid, eid, lid, nid, str|
      off = strings.bytesize
      strings << str.b
      [pid, eid, lid, nid, str.bytesize, off].pack("n6")
    end
    [0, records.size, 6 + (records.size * 12)].pack("n3") + recs.join + strings
  end

  def utf16(str)
    str.encode("UTF-16BE").b
  end

  def mac_roman(str)
    str.encode("macRoman").b
  end
end
