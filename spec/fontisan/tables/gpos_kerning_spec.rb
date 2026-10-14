# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/gpos_builder"

RSpec.describe Fontisan::Tables::Gpos do
  include GposBuilder

  let(:individual) { gpos_pair_one({ 2 => { 3 => -29, 4 => 15 } }) }
  let(:class_based) { gpos_pair_two }

  describe "#kern_pairs" do
    it "queries signed font units and enumerates explicit pairs" do
      pairs = described_class.read(gpos_binary([gpos_lookup([individual])])).kern_pairs
      expect(pairs[[2, 3]]).to eq(-29)
      expect(pairs[[3, 2]]).to eq(0)
      expect(pairs.to_h).to eq({ [2, 3] => -29, [2, 4] => 15 })
    end

    [1, 2].each do |coverage_format|
      [1, 2].each do |class_format|
        it "resolves coverage #{coverage_format} and classes #{class_format}, including class zero" do
          subtable = gpos_pair_two(coverage: [1, 2], coverage_format: coverage_format,
                                   class_format: class_format, matrix: [[-5, -7], [-11, -29]])
          pairs = described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs(glyph_count: 5)
          expect(pairs[[2, 3]]).to eq(-29)
          expect(pairs[[2, 4]]).to eq(-11)
          expect(pairs[[1, 3]]).to eq(-7)
          expect(pairs[[4, 3]]).to eq(0)
          expect(pairs.to_h).to include([1, 0] => -5, [2, 4] => -11)
          expect(pairs.to_h.keys.flatten.max).to eq(4)
        end
      end

      it "resolves individual coverage #{coverage_format}" do
        subtable = gpos_pair_one({ 2 => { 3 => -29 } }, coverage_format: coverage_format)
        expect(described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs.to_h)
          .to eq({ [2, 3] => -29 })
      end
    end

    it "does not match glyphs below or between Coverage2 ranges" do
      subtable = gpos_pair_two(coverage: [2, 4], coverage_format: 2, matrix: [[-5, -7], [-11, -29]])
      pairs = described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs
      [1, 3, 5].each { |left| expect(pairs[[left, 3]]).to eq(0) }
    end

    it "returns the collection after yielding pairs" do
      pairs = described_class.read(gpos_binary([gpos_lookup([individual])])).kern_pairs
      yielded = []
      expect(pairs.each { |pair, value| yielded << [pair, value] }).to equal(pairs)
      expect(yielded).to eq([[[2, 3], -29], [[2, 4], 15]])
    end

    it "keeps queries stable when callers edit table bytes or yielded pairs" do
      table = described_class.read(gpos_binary([gpos_lookup([gpos_pair_two(class_format: 1)])]))
      pairs = table.kern_pairs(glyph_count: 5)
      expected = pairs.to_h
      pairs.each.first[0].replace([65535, 65535])
      table.raw_data.replace("\x00".b * table.raw_data.bytesize)
      expect(pairs[[2, 3]]).to eq(-29)
      expect(pairs.to_h).to eq(expected)
    end

    it "preserves the signed xAdvance limits and zero" do
      [-32768, -1, 0, 32767].each do |value|
        data = gpos_binary([gpos_lookup([gpos_pair_one({ 2 => { 3 => value } })])])
        expect(described_class.read(data).kern_pairs[[2, 3]]).to eq(value)
      end
    end

    it "consumes all value fields and both records without treating offsets as advances" do
      [gpos_pair_one({ 2 => { 3 => -29, 4 => 15 } }, value_format: 255, second_format: 255),
       gpos_pair_two(value_format: 255, second_format: 255)].each do |subtable|
        pairs = described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs
        expect(pairs[[2, 3]]).to eq(-29)
      end
    end

    it "returns zero when value1 has no xAdvance" do
      [gpos_pair_one({ 2 => { 3 => -29 } }, value_format: 3, second_format: 4),
       gpos_pair_two(value_format: 0, second_format: 4)].each do |subtable|
        expect(described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs[[2, 3]]).to eq(0)
      end
    end

    it "stops at a matched zero subtable and sums each distinct lookup once" do
      zero = gpos_pair_one({ 2 => { 3 => 0 } })
      second = gpos_pair_one({ 2 => { 3 => -8 } })
      data = gpos_binary([gpos_lookup([zero, individual]), gpos_lookup([second])], indices: [1, 0, 1])
      pairs = described_class.read(data).kern_pairs
      expect(pairs[[2, 3]]).to eq(-8)
      expect(pairs[[2, 4]]).to eq(15)
      expect(pairs.to_h).to eq({ [2, 3] => -8, [2, 4] => 15 })
    end

    it "treats a covered zero class cell as a match before later subtables" do
      zero_classes = gpos_pair_two(matrix: [[0, 0], [0, 0]])
      data = gpos_binary([gpos_lookup([zero_classes, individual])])
      pairs = described_class.read(data).kern_pairs(glyph_count: 5)
      expect(pairs[[2, 3]]).to eq(0)
      expect(pairs.to_h).to eq({})
    end

    it "adds nonzero adjustments from independent lookups" do
      second = gpos_pair_one({ 2 => { 3 => -8 } })
      data = gpos_binary([gpos_lookup([individual]), gpos_lookup([second])])
      expect(described_class.read(data).kern_pairs[[2, 3]]).to eq(-37)
    end

    it "tries later subtables when the first does not match" do
      absent = gpos_pair_one({ 2 => { 5 => -3 } })
      pairs = described_class.read(gpos_binary([gpos_lookup([absent, individual])])).kern_pairs
      expect(pairs[[2, 3]]).to eq(-29)
    end

    it "omits zero net pairs and honors bounds on individual enumeration" do
      inverse = gpos_pair_one({ 2 => { 3 => 29 } })
      data = gpos_binary([gpos_lookup([individual]), gpos_lookup([inverse])])
      expect(described_class.read(data).kern_pairs(glyph_count: 4).to_h).to eq({})
    end

    it "requires explicit glyph count only for class enumeration and supports early exit" do
      pairs = described_class.read(gpos_binary([gpos_lookup([class_based])])).kern_pairs
      expect(pairs[[2, 3]]).to eq(-29)
      expect { pairs.to_h }.to raise_error(ArgumentError, /glyph_count/)
      bounded = described_class.read(gpos_binary([gpos_lookup([class_based])])).kern_pairs(glyph_count: 65536)
      first, array_bytes = gpos_measured_first(bounded)
      expect(first).to eq([[2, 0], -11])
      expect(array_bytes).to be < 64_000
    end

    it "selects the requested script and feature, including a required feature" do
      data = gpos_binary([gpos_lookup([individual])], script_tag: "DFLT", feature_tag: "dist", required: true)
      table = described_class.read(data)
      expect(table.kern_pairs.to_h).to eq({})
      expect(table.kern_pairs(script_tag: "DFLT").to_h).to eq({})
      expect(table.kern_pairs(script_tag: "DFLT", feature_tag: "dist")[[2, 3]]).to eq(-29)
    end

    it "does not union named language systems into the default language" do
      data = gpos_binary([gpos_lookup([individual])], default: false, language_feature: true)
      expect(described_class.read(data).kern_pairs.to_h).to eq({})
    end

    it "returns an empty collection when there are no script or feature lists" do
      expect(described_class.read([1, 0, 0, 0, 0].pack("n*")).kern_pairs.to_h).to eq({})
    end

    it "leaves malformed later lists unread when no script or feature is selected" do
      unknown_script = gpos_binary([gpos_lookup([individual])], script_tag: "DFLT")
      unknown_script[6, 2] = [65535].pack("n")
      unknown_feature = gpos_binary([gpos_lookup([individual])], feature_tag: "dist")
      unknown_feature[8, 2] = [65535].pack("n")
      [unknown_script, unknown_feature].each do |data|
        expect(described_class.read(data).kern_pairs.to_h).to eq({})
      end
    end

    it "skips other lookup types and handles the mark-filtering-set field" do
      data = gpos_binary([gpos_lookup(["ignored"], type: 1), gpos_lookup([individual], flags: 16)])
      expect(described_class.read(data).kern_pairs[[2, 3]]).to eq(-29)
    end

    [-1, 65537, 2.5, "5"].each do |glyph_count|
      it "rejects invalid glyph count #{glyph_count.inspect}" do
        expect { described_class.read(gpos_binary([])).kern_pairs(glyph_count: glyph_count) }
          .to raise_error(ArgumentError, /glyph_count/)
      end
    end

    it "rejects invalid glyph pair queries" do
      pairs = described_class.read(gpos_binary([gpos_lookup([individual])])).kern_pairs
      [[-1, 2], [2, 65536], [2], [2, "3"]].each do |pair|
        expect { pairs[pair] }.to raise_error(ArgumentError, /glyph/)
      end
    end
  end

  describe "shared binary data" do
    it "keeps aliased lookup decoding bounded while retaining logical lookup sums" do
      pairs, allocations = gpos_measured_pairs(gpos_lookup_alias_binary(count: 32), glyph_count: 1)
      expect(allocations).to be < 20_000
      expect(pairs[[0, 0]]).to eq(-32)
      first, array_bytes = gpos_measured_first(pairs)
      expect(first).to eq([[0, 0], -32])
      expect(array_bytes).to be < 64_000
    end

    it "keeps shared PairSet decoding bounded without dropping first glyphs" do
      pairs, allocations = gpos_measured_pairs(gpos_pair_set_alias_binary(count: 32), glyph_count: 2)
      expect(allocations).to be < 50_000
      expect(pairs[[0, 0]]).to eq(-1)
      expect(pairs[[31, 4095]]).to eq(-1)
      expect(pairs.to_h).to eq({ [0, 0] => -1, [0, 1] => -1, [1, 0] => -1, [1, 1] => -1 })
    end

    it "keeps full-domain Coverage2 compact before bounded enumeration" do
      data = gpos_shared_coverage_binary(count: 32, glyphs: 65536)
      pairs, _allocations, array_bytes = gpos_measured_pairs(data, glyph_count: 1)
      expect(array_bytes).to be < 64_000
      expect(pairs[[65535, 65535]]).to eq(-32)
      expect(pairs.each.first).to eq([[0, 0], -32])
    end

    it "keeps overlapping ClassDef1 data compact" do
      data = gpos_overlapping_classes_binary
      pairs, allocations = gpos_measured_pairs(data, glyph_count: 1)
      expect(allocations).to be < 20_000
      expect(pairs[[2, 0]]).to eq(-5025)
    end

    it "keeps Coverage sharing across distinct PairPos tables bounded" do
      pairs, allocations = gpos_measured_pairs(gpos_shared_coverage_binary(count: 32), glyph_count: 1)
      expect(allocations).to be < 20_000
      expect(pairs[[0, 0]]).to eq(-32)
      first, array_bytes = gpos_measured_first(pairs)
      expect(first).to eq([[0, 0], -32])
      expect(array_bytes).to be < 64_000
    end
  end

  describe "shared decode contexts" do
    it "decodes shared PairSets separately for different value1 formats" do
      pairs = described_class.read(gpos_shared_pair_set_binary).kern_pairs
      expect(pairs[[2, 3]]).to eq(-29)
    end

    it "decodes shared PairSets separately for different value2 strides" do
      data = gpos_shared_pair_set_binary(first_formats: [4, 4], second_formats: [0, 1],
                                         records: [2, 3, -29, 4, 5, 15, 0])
      pairs = described_class.read(data).kern_pairs
      expect(pairs[[2, 3]]).to eq(-58)
      expect(pairs[[2, 4]]).to eq(5)
      expect(pairs[[2, 5]]).to eq(15)
    end

    it "validates shared ClassDefs against both parent class counts" do
      subtable = gpos_pair_two(first: { 2 => 1 }, second: {}, matrix: [[0], [-29]])
      subtable[10, 2] = subtable.byteslice(8, 2)
      expect { described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs }
        .to raise_error(Fontisan::ParseError, /class definition/)
    end

    it "decodes aliased features once while deduplicating referenced lookups" do
      pairs, allocations = gpos_measured_pairs(gpos_feature_alias_binary, glyph_count: 1)
      expect(allocations).to be < 40_000
      expect(pairs[[0, 0]]).to eq(-1)
    end
  end

  describe "malformed selected data" do
    it "rejects every truncated suffix of a selected synthetic table" do
      [individual, class_based].each do |subtable|
        data = gpos_binary([gpos_lookup([subtable])])
        (10...data.bytesize).each do |length|
          expect { described_class.read(data.byteslice(0, length)).kern_pairs }
            .to raise_error(Fontisan::ParseError), "accepted #{length}/#{data.bytesize} bytes"
        end
      end
    end

    it "rejects reserved value-format bits and unsupported pair formats" do
      [0x100, 0xffff].each do |value_format|
        subtable = individual.dup
        subtable[4, 2] = [value_format].pack("n")
        expect { described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs }
          .to raise_error(Fontisan::ParseError)
      end
      [individual, class_based].each do |valid|
        subtable = valid.dup
        subtable[0, 2] = [3].pack("n")
        expect { described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs }
          .to raise_error(Fontisan::ParseError, /Unsupported PairPos format/)
      end
    end

    it "rejects unknown Coverage and ClassDef formats in otherwise valid class tables" do
      [1, 2].each do |format|
        valid = gpos_pair_two(coverage_format: format, class_format: format)
        { 2 => "Coverage", 8 => "ClassDef", 10 => "ClassDef" }.each do |field, kind|
          malformed = valid.dup
          offset = malformed.byteslice(field, 2).unpack1("n")
          malformed[offset, 2] = [3].pack("n")
          expect { described_class.read(gpos_binary([gpos_lookup([malformed])])).kern_pairs }
            .to raise_error(Fontisan::ParseError, /Unsupported #{kind} format/)
        end
      end
    end

    it "rejects ClassDef1 arrays that extend beyond the glyph-ID domain" do
      [65535, 65536].each do |last|
        subtable = gpos_pair_two(coverage: [65535], first: { 65535 => 0, last => 0 },
                                 second: {}, matrix: [[-29]], class_format: 1)
        table = described_class.read(gpos_binary([gpos_lookup([subtable])]))
        if last == 65535
          expect(table.kern_pairs[[65535, 0]]).to eq(-29)
        else
          expect { table.kern_pairs }.to raise_error(Fontisan::ParseError, /class definition/)
        end
      end
    end

    it "rejects an invalid feature index with valid Script and LangSys offsets" do
      data = gpos_binary([gpos_lookup([individual])])
      script_list = data.byteslice(4, 2).unpack1("n")
      script = script_list + data.byteslice(script_list + 6, 2).unpack1("n")
      language = script + data.byteslice(script, 2).unpack1("n")
      data[language + 6, 2] = [2].pack("n")
      expect { described_class.read(data).kern_pairs }
        .to raise_error(Fontisan::ParseError, /feature index 2/)
    end

    it "requires the optional mark-filtering word even for an empty lookup" do
      data = gpos_binary([gpos_lookup([], flags: 16)])
      expect(described_class.read(data).kern_pairs.to_h).to eq({})
      expect { described_class.read(data.byteslice(0...-2)).kern_pairs }
        .to raise_error(Fontisan::ParseError, /Truncated GPOS/)
    end

    it "rejects malformed overlapping Feature indices before repeated decoding" do
      data = gpos_overlapping_features_binary
      before = GC.stat(:total_allocated_objects)
      expect { described_class.read(data).kern_pairs }
        .to raise_error(Fontisan::ParseError, /lookup index 1000/)
      expect(GC.stat(:total_allocated_objects) - before).to be < 20_000
    end

    it "rejects offsets into headers, off-table offsets, and invalid feature/lookup indices" do
      data = gpos_binary([gpos_lookup([individual])])
      feature_base = data.byteslice(6, 2).unpack1("n")
      lookup_base = data.byteslice(8, 2).unpack1("n")
      [[4, 9], [6, 65535], [8, 0], [18, 2], [feature_base + 6, 2],
       [feature_base + 12, 3], [lookup_base + 2, 2]].each do |offset, value|
        malformed = data.dup
        malformed[offset, 2] = [value].pack("n")
        expect { described_class.read(malformed).kern_pairs }
          .to raise_error(Fontisan::ParseError), "accepted mutation #{offset}=#{value}"
      end
    end

    it "rejects extra PairSets even when their offsets are valid" do
      malformed = individual.dup
      malformed.insert(12, [20].pack("n"))
      malformed[2, 2] = [14].pack("n")
      malformed[8, 4] = [2, 20].pack("n*")
      expect { described_class.read(gpos_binary([gpos_lookup([malformed])])).kern_pairs }
        .to raise_error(Fontisan::ParseError, /PairSet count/)
    end

    it "rejects inconsistent coverage and malformed class definitions" do
      [[2, 0], [2, 65535], [8, 0], [10, 0], [12, 0], [14, 0]].each do |offset, value|
        malformed = class_based.dup
        malformed[offset, 2] = [value].pack("n")
        expect { described_class.read(gpos_binary([gpos_lookup([malformed])])).kern_pairs }
          .to raise_error(Fontisan::ParseError)
      end
      coverage_offset = individual.byteslice(2, 2).unpack1("n")
      [[coverage_offset, 3], [8, 2]].each do |offset, value|
        malformed = individual.dup
        malformed[offset, 2] = [value].pack("n")
        expect { described_class.read(gpos_binary([gpos_lookup([malformed])])).kern_pairs }
          .to raise_error(Fontisan::ParseError)
      end
    end

    it "rejects unordered coverage ranges and class ranges" do
      malformed_coverage = gpos_pair_one({ 2 => { 3 => -29 }, 4 => { 3 => -15 } }, coverage_format: 2)
      coverage_offset = malformed_coverage.byteslice(2, 2).unpack1("n")
      malformed_coverage[coverage_offset + 10, 2] = [1].pack("n")
      malformed_classes = gpos_pair_two(second: { 3 => 1, 4 => 1 })
      class_offset = malformed_classes.byteslice(10, 2).unpack1("n")
      malformed_classes[class_offset + 10, 2] = [2].pack("n")
      [malformed_coverage, malformed_classes].each do |subtable|
        expect { described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs }
          .to raise_error(Fontisan::ParseError)
      end
    end

    it "rejects unordered Coverage1 glyphs with otherwise valid offsets" do
      malformed = gpos_pair_one({ 2 => { 3 => -29 }, 4 => { 3 => -15 } })
      offset = malformed.byteslice(2, 2).unpack1("n")
      malformed[offset + 4, 4] = [4, 2].pack("n*")
      expect { described_class.read(gpos_binary([gpos_lookup([malformed])])).kern_pairs }
        .to raise_error(Fontisan::ParseError, /glyph IDs/)
    end

    it "rejects duplicate PairSet second glyph IDs with otherwise valid records" do
      malformed = individual.dup
      offset = malformed.byteslice(10, 2).unpack1("n")
      malformed[offset + 6, 2] = [3].pack("n")
      expect { described_class.read(gpos_binary([gpos_lookup([malformed])])).kern_pairs }
        .to raise_error(Fontisan::ParseError, /glyph IDs/)
    end

    it "rejects inconsistent Coverage2 indices with otherwise ordered ranges" do
      malformed = gpos_pair_two(coverage_format: 2)
      offset = malformed.byteslice(2, 2).unpack1("n")
      malformed[offset + 8, 2] = [1].pack("n")
      expect { described_class.read(gpos_binary([gpos_lookup([malformed])])).kern_pairs }
        .to raise_error(Fontisan::ParseError, /coverage range/)
    end

    it "rejects empty matrices even when class definitions contain no explicit assignments" do
      [12, 14].each do |offset|
        malformed = gpos_pair_two(first: {}, second: {}, matrix: [[0]], value_format: 0)
        malformed[offset, 2] = [0].pack("n")
        expect { described_class.read(gpos_binary([gpos_lookup([malformed])])).kern_pairs }
          .to raise_error(Fontisan::ParseError, /Empty/)
      end
    end

    it "rejects invalid class IDs and queries a huge zero-width class matrix without expansion" do
      subtable = gpos_pair_two(first: { 2 => 2 })
      expect { described_class.read(gpos_binary([gpos_lookup([subtable])])).kern_pairs }
        .to raise_error(Fontisan::ParseError)
      compact = gpos_pair_two(value_format: 0)
      compact[12, 4] = [65535, 65535].pack("n*")
      expect(described_class.read(gpos_binary([gpos_lookup([compact])])).kern_pairs[[2, 3]]).to eq(0)
    end
  end

  describe "loading in a fresh process" do
    {
      "pair parser first" => ["fontisan/tables/gpos/pair_position", "fontisan"],
      "collection first" => ["fontisan/tables/gpos/kerning_pairs", "fontisan"],
      "facade first" => ["fontisan/tables/gpos", "fontisan"],
      "gem first" => ["fontisan", "fontisan/tables/gpos/pair_position", "fontisan/tables/gpos/kerning_pairs"],
    }.each do |name, order|
      it "keeps the table reader intact with #{name}" do
        path = font_fixture_path("Libertinus", "static/TTF/LibertinusSerif-Regular.ttf")
        output, errors, status = gpos_load_order(order, path)
        expect(status.exitstatus).to eq(0), errors
        expect(output).to eq("ok\n")
        expect(errors).to eq("")
      end
    end
  end

  describe "Libertinus kerning" do
    %w[TTF OTF].each do |format|
      it "matches the independently measured AV adjustment in #{format}" do
        extension = format.downcase
        path = font_fixture_path("Libertinus", "static/#{format}/LibertinusSerif-Regular.#{extension}")
        font = Fontisan::FontLoader.load(path)
        pairs = font.table("GPOS").kern_pairs
        expect(pairs[[34, 55]]).to eq(-112)
      end
    end
  end
end
