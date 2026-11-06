# frozen_string_literal: true

require "spec_helper"

# flip_cmap (fontist/fontisan#156): a format 4 segCountX2 past the arrays inside
# the declared length raised NoMethodError from Cmap#unicode_mappings; the cut
# segments are now skipped, as the native tier does.
RSpec.describe Fontisan::Tables::Cmap do
  def cmap_with_seg_count(seg_count_x2)
    sub = [4, 0, 0, 6, 0, 0, 0, 0].pack("n*")
    sub += [0x41, 0xFFFF].pack("n*") + [0].pack("n") + [0x41, 0xFFFF].pack("n*") + [1, 1].pack("n*") + [0, 0].pack("n*")
    sub[2, 2] = [sub.bytesize].pack("n")
    sub[6, 2] = [seg_count_x2].pack("n")
    raw = [0, 1, 3, 1, 12].pack("nnnnN") + sub
    described_class.read(raw)
  end

  it "keeps the complete segments when segCountX2 overshoots" do
    expect { cmap_with_seg_count(400).unicode_mappings }.not_to raise_error
  end
end
