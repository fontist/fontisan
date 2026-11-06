# frozen_string_literal: true

require "fontisan"

# Builds a WOFF2 collection whose tables all use the null transform
# (glyf/loca transform version 3, hmtx version 0): spec-valid input that
# Fontisan's own encoder never produces, so a spec cannot get it from there.
module Woff2NullCollection
  module_function

  # @param faces [Array<Hash{String => String}>] tag => bytes per member
  # @return [String] binary WOFF2 collection
  def build(faces)
    entries = []
    members = faces.map { |tables| tables.sort.map { |tag, data| index_of(entries, tag, data) } }
    directory = entries.map { |tag, data| directory_entry(tag, data) }.join
    stream = Brotli.deflate(entries.map(&:last).join, quality: 5)
    payload = directory + collection_header(members) + stream
    sfnt_size = 12 + (entries.size * 16) + entries.sum { |_, d| (d.bytesize + 3) & ~3 }
    header = ["wOF2", "ttcf", 48 + payload.bytesize, entries.size, 0, sfnt_size,
              stream.bytesize, 1, 0, 0, 0, 0, 0, 0].pack("a4a4NnnNNnnNNNNN")
    header + payload
  end

  def index_of(entries, tag, data)
    found = entries.index { |t, d| t == tag && d == data }
    return found if found

    entries << [tag, data]
    entries.size - 1
  end

  def directory_entry(tag, data)
    known = Fontisan::Woff2::Directory::KNOWN_TAGS.index(tag)
    version = %w[glyf loca].include?(tag) ? 3 : 0
    flags = [(known || 63) | (version << 6)].pack("C")
    flags += tag.b unless known
    flags + base128(data.bytesize)
  end

  def base128(value)
    groups = [value & 0x7f]
    groups.unshift(0x80 | (value & 0x7f)) while (value >>= 7).positive?
    groups.pack("C*")
  end

  def collection_header(members)
    out = [0x00010000].pack("N") + [members.size].pack("C")
    members.each do |indices|
      out += [indices.size].pack("C") + [0x00010000].pack("N") + indices.pack("C*")
    end
    out
  end
end
