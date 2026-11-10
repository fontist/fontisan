# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# A zero-length table shares its offset with the next table (the empty name
# table of quirk-empty-name-table sits where post starts). The batched
# metadata read sorted by offset with an unstable sort, so whether `post`
# kept its bytes depended on the platform's qsort. Directory order is the
# tiebreak now; both orders must read post in full.
RSpec.describe Fontisan::SfntFont, "#read_metadata_tables_batched" do
  let(:source) { File.expand_path("../../corpus/derived/quirk-empty-name-table.ttf", __dir__) }

  def post_length_after_swap(bytes, swap)
    count = bytes[4, 2].unpack1("n")
    dir = Array.new(count) { |i| bytes[12 + (16 * i), 16] }
    name_i = dir.index { |e| e[0, 4] == "name" }
    post_i = dir.index { |e| e[0, 4] == "post" }
    dir[name_i], dir[post_i] = dir[post_i], dir[name_i] if swap
    out = bytes.dup
    out[12, 16 * count] = dir.join
    Dir.mktmpdir do |d|
      path = File.join(d, "f.ttf")
      File.binwrite(path, out)
      Fontisan::FontLoader.load(path, mode: :metadata, lazy: false).table_data["post"].bytesize
    end
  end

  it "reads post in full with the zero-length table first in the directory" do
    expect(post_length_after_swap(File.binread(source), false)).to eq(55)
  end

  it "reads post in full with the zero-length table last in the directory" do
    expect(post_length_after_swap(File.binread(source), true)).to eq(55)
  end
end
