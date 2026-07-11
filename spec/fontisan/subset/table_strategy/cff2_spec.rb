# frozen_string_literal: true

require "spec_helper"

# Build a minimal synthetic CFF2 binary for testing the subsetter.
# The CFF2 has:
#   - Header (5 bytes)
#   - Top DICT (pointers to CharStrings, FDArray, FDSelect, VStore)
#   - Global Subr INDEX (empty)
#   - Variable Store (minimal)
#   - FDArray INDEX (one Font DICT with one Private DICT)
#   - FDSelect (format 0)
#   - CharStrings INDEX (N glyphs, each a minimal "endchar" charstring)
module Cff2SpecHelper
  OP_CHARSTRINGS = 17
  OP_VSTORE = 24
  OP_FDARRAY = [12, 36].freeze
  OP_FDSELECT = [12, 37].freeze
  OP_PRIVATE = 18

  class << self
    def encode_int(value)
      Fontisan::Tables::Cff2::DictEncoder.encode_integer(value)
    end

    def encode_op(op)
      Fontisan::Tables::Cff2::DictEncoder.encode_operator(op)
    end

    def encode_dict(entries)
      io = +""
      entries.each do |op, vals|
        Array(vals).each { |v| io << encode_int(v) }
        io << encode_op(op)
      end
      io
    end

    def build_empty_index
      [0].pack("N") # count = 0
    end

    def build_index(items)
      Fontisan::Tables::Cff2::IndexBuilder.build(items)
    end

    # Build a minimal ItemVariationStore with 1 region, 1 data entry.
    def build_vstore
      io = +""
      io << [1].pack("n")          # format
      io << [8 + 4].pack("N")      # variationRegionListOffset (after header + 1 offset)
      io << [1].pack("n")          # itemVariationDataCount
      io << [8 + 4 + 16].pack("N") # itemVariationDataOffsets[0]

      # VariationRegionList
      io << [1].pack("n")  # axisCount
      io << [1].pack("n")  # regionCount
      # Region: 3 × F2DOT14 for 1 axis
      io << [0, 0x4000, 0x4000].pack("nnn") # start=0, peak=1.0, end=1.0

      # ItemVariationData
      io << [1].pack("n")  # itemCount
      io << [1].pack("n")  # shortDeltaCount
      io << [1].pack("n")  # regionIndexCount
      io << [0].pack("n")  # regionIndex[0] = 0
      io << [100].pack("s>") # deltaSets[0] = +100 (int16)
      io
    end

    # Build a CFF2 table with N glyphs, each with a minimal charstring.
    def build_cff2(num_glyphs:)
      endchar = "\x0e".b # Type 2 endchar

      charstrings = build_index(Array.new(num_glyphs) { endchar })
      gsubr = build_empty_index
      vstore = build_vstore
      priv_dict = encode_dict([]) # empty Private DICT
      font_dict = encode_dict([[OP_PRIVATE, [priv_dict.bytesize, 0]]])
      fdarray = build_index([font_dict])
      fdselect = ([0] + Array.new(num_glyphs) { 0 }).pack("C*") # format 0, all FD=0

      # Layout: Header(5) | TopDICT | GSubr | VStore | FDArray | PrivDict | FDSelect | CharStrings
      # Top DICT offsets need to be computed. Start with estimate.
      td_entries = {}
      td_size_guess = 30

      10.times do
        pos = 5 + td_size_guess
        offsets = {
          gsubr: pos,
          vstore: pos + gsubr.bytesize,
          fdarray: pos + gsubr.bytesize + vstore.bytesize,
          priv: pos + gsubr.bytesize + vstore.bytesize + fdarray.bytesize,
          fdselect: pos + gsubr.bytesize + vstore.bytesize + fdarray.bytesize + priv_dict.bytesize,
          charstrings: pos + gsubr.bytesize + vstore.bytesize + fdarray.bytesize + priv_dict.bytesize + fdselect.bytesize,
        }

        td_entries = {
          OP_CHARSTRINGS => offsets[:charstrings],
          OP_VSTORE => offsets[:vstore],
          OP_FDARRAY => offsets[:fdarray],
          OP_FDSELECT => offsets[:fdselect],
        }
        # Update Font DICT's Private offset
        font_dict = encode_dict([[OP_PRIVATE, [priv_dict.bytesize, offsets[:priv]]]])
        fdarray = build_index([font_dict])
        # Recompute fdselect/charstrings offsets since fdarray size may change
        offsets[:fdselect] = offsets[:fdarray] + fdarray.bytesize
        offsets[:charstrings] = offsets[:fdselect] + fdselect.bytesize
        td_entries[OP_FDSELECT] = offsets[:fdselect]
        td_entries[OP_CHARSTRINGS] = offsets[:charstrings]

        td = encode_dict(td_entries)
        break if td.bytesize == td_size_guess

        td_size_guess = td.bytesize
      end

      header = Fontisan::Tables::Cff2::Header.build(top_dict_size: td_size_guess)
      encode_dict(td_entries)

      # Rebuild font_dict with correct offset
      priv_offset = 5 + td_size_guess + gsubr.bytesize + vstore.bytesize + fdarray.bytesize
      font_dict = encode_dict([[OP_PRIVATE, [priv_dict.bytesize, priv_offset]]])
      fdarray = build_index([font_dict])
      fdselect_offset = priv_offset + priv_dict.bytesize
      charstrings_offset = fdselect_offset + fdselect.bytesize
      td_entries[OP_CHARSTRINGS] = charstrings_offset
      td_entries[OP_FDSELECT] = fdselect_offset
      td = encode_dict(td_entries)

      io = +""
      io << header
      io << td
      io << gsubr
      io << vstore
      io << fdarray
      io << priv_dict
      io << fdselect
      io << charstrings
      io
    end
  end
end

RSpec.describe Fontisan::Subset::TableStrategy::Cff2 do
  let(:cff2_bytes) { Cff2SpecHelper.build_cff2(num_glyphs: 10) }
  let(:font) do
    # Minimal stub font object that returns the CFF2 table bytes.
    Struct.new(:table_obj).new(
      Struct.new(:raw_data).new(cff2_bytes),
    )
  end

  before do
    allow(font).to receive(:table).with("CFF2").and_return(font.table_obj)
    allow(font).to receive(:respond_to).with(:table).and_return(true)
  end

  describe ".call" do
    it "produces valid CFF2 output with fewer charstrings" do
      mapping = Fontisan::Subset::GlyphMapping.new([0, 1, 2])
      context = Fontisan::Subset::SubsetContext.new(
        font: font, mapping: mapping, options: nil, state: nil,
      )

      result = described_class.call(context: context, tag: "CFF2", table: font.table_obj)
      expect(result).not_to be_empty

      reader = Fontisan::Tables::Cff2::TableReader.new(result)
      reader.read_top_dict

      cs_offset = reader.top_dict[Cff2SpecHelper::OP_CHARSTRINGS]
      cs_index = Fontisan::Tables::Cff2::Index.read(result, cs_offset)
      expect(cs_index.count).to eq(3)
    end

    it "preserves the Variable Store" do
      mapping = Fontisan::Subset::GlyphMapping.new([0, 1])
      context = Fontisan::Subset::SubsetContext.new(
        font: font, mapping: mapping, options: nil, state: nil,
      )

      result = described_class.call(context: context, tag: "CFF2", table: font.table_obj)

      reader = Fontisan::Tables::Cff2::TableReader.new(result)
      reader.read_top_dict
      expect(reader.top_dict[Cff2SpecHelper::OP_VSTORE]).to be_positive
    end

    it "preserves the FDSelect with correct glyph count" do
      mapping = Fontisan::Subset::GlyphMapping.new([0, 1, 2])
      context = Fontisan::Subset::SubsetContext.new(
        font: font, mapping: mapping, options: nil, state: nil,
      )

      result = described_class.call(context: context, tag: "CFF2", table: font.table_obj)

      reader = Fontisan::Tables::Cff2::TableReader.new(result)
      reader.read_top_dict
      fds_offset = reader.top_dict[Cff2SpecHelper::OP_FDSELECT]
      expect(fds_offset).to be_positive

      assignments = Fontisan::Tables::Cff2::FdSelect.read(
        result, fds_offset, 3
      )
      expect(assignments.size).to eq(3)
    end

    it "returns the raw bytes when the source is empty" do
      empty_font = Struct.new(:table_obj).new(nil)
      allow(empty_font).to receive(:respond_to).with(:table).and_return(true)
      allow(empty_font).to receive(:table).with("CFF2").and_return(nil)

      mapping = Fontisan::Subset::GlyphMapping.new([0])
      context = Fontisan::Subset::SubsetContext.new(
        font: empty_font, mapping: mapping, options: nil, state: nil,
      )

      result = described_class.call(context: context, tag: "CFF2", table: nil)
      expect(result).to be_nil
    end
  end
end
