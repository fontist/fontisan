# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher/partition_strategy"

RSpec.describe Fontisan::Stitcher::PartitionStrategy::ByPlane do
  let(:partitioner) { described_class.new }

  describe "#call" do
    it "returns a Blueprint with no partitions for an empty cp_map" do
      blueprint = partitioner.call({})
      expect(blueprint).to be_a(Fontisan::Stitcher::PartitionStrategy::Blueprint)
      expect(blueprint.partitions).to eq([])
    end

    it "groups all BMP codepoints into one :plane_0 partition" do
      cp_map = { 0x41 => :latin, 0x4E00 => :cjk }
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to eq([:plane_0])
      expect(blueprint.partitions.first.cps).to contain_exactly(0x41, 0x4E00)
    end

    it "emits separate partitions per plane when codepoints span planes" do
      cp_map = { 0x41 => :latin, 0x20000 => :cjk }
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to eq(%i[plane_0 plane_2])
    end

    it "sub-splits a plane that exceeds the cap" do
      # 200 BMP codepoints under cap=100 → multiple :plane_0_X partitions
      cp_map = (0x41..(0x41 + 199)).each_with_index.to_h { |cp, _i| [cp, :donor] }
      blueprint = partitioner.call(cp_map, cap: 100)

      names = blueprint.names
      expect(names).to all(match(/\Aplane_0_[a-z]\z/))
      expect(names.size).to be >= 2
    end

    it "raises PartitionCapExceededError when a single CJK Ext block exceeds the cap" do
      # CJK Ext B alone is 0x2A700..0x2B73F (~6592 cps). With cap=100 it
      # cannot be sub-split further.
      cp_map = (0x2A700..0x2A700 + 200).each_with_index.to_h { |cp, _i| [cp, :cjk] }
      expect do
        partitioner.call(cp_map, cap: 100)
      end.to raise_error(Fontisan::PartitionCapExceededError, /single Unicode block/)
    end
  end

  describe "Partition#apply_to" do
    let(:ufo) { Fontisan::Ufo }

    def make_font_with(name, cp)
      font = ufo::Font.new
      font.info.units_per_em = 1000
      font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

      g = ufo::Glyph.new(name: name)
      g.width = 500
      g.add_unicode(cp)
      g.add_contour(ufo::Contour.new([
                                       ufo::Point.new(x: 0, y: 0, type: "line"),
                                       ufo::Point.new(x: 100, y: 0,   type: "line"),
                                       ufo::Point.new(x: 100, y: 100, type: "line"),
                                     ]))
      font.glyphs[name] = g
      font
    end

    it "pushes bindings into the Stitcher via include_codepoints_map" do
      cp_map = { 0x41 => :latin, 0x4E00 => :cjk }
      blueprint = partitioner.call(cp_map)

      donor_latin = make_font_with("A", 0x41)
      donor_cjk   = make_font_with("uni4E00", 0x4E00)

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:latin, donor_latin)
      stitcher.add_source(:cjk, donor_cjk)

      declared = blueprint.apply_to(stitcher)
      expect(declared).to eq([:plane_0])
      expect(stitcher.subfonts[:plane_0]).not_to be_empty
    end
  end
end
