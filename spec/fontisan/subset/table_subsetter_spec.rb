# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Subset::TableSubsetter do
  let(:font_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::TrueTypeFont.from_file(font_path) }
  let(:glyph_ids) { [0, 1, 65, 66, 67] } # .notdef, NULL, A, B, C
  let(:mapping) do
    Fontisan::Subset::GlyphMapping.new(glyph_ids, retain_gids: false)
  end
  let(:options) { Fontisan::Subset::Options.new }
  let(:subsetter) { described_class.new(font, mapping, options) }

  describe "#initialize" do
    it "initializes with font, mapping, and options" do
      expect(subsetter.font).to eq(font)
      expect(subsetter.mapping).to eq(mapping)
      expect(subsetter.options).to eq(options)
    end
  end

  describe "#subset_table" do
    it "delegates to subset_maxp for maxp table" do
      maxp = font.table("maxp")
      result = subsetter.subset_table("maxp", maxp)
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "delegates to subset_hhea for hhea table" do
      hhea = font.table("hhea")
      result = subsetter.subset_table("hhea", hhea)
      expect(result).to be_a(String)
    end

    it "delegates to subset_hmtx for hmtx table" do
      hmtx = font.table("hmtx")
      result = subsetter.subset_table("hmtx", hmtx)
      expect(result).to be_a(String)
    end

    it "passes through unknown tables" do
      name_table = font.table("name")
      table_data_hash = font.table_data.dup
      table_data_hash["name"] = "test_data"
      allow(font).to receive(:table_data).and_return(table_data_hash)
      result = subsetter.subset_table("name", name_table)
      expect(result).to eq("test_data")
    end
  end

  describe "#subset_maxp" do
    it "updates numGlyphs field" do
      maxp = font.table("maxp")
      result = subsetter.subset_maxp(maxp)

      # Parse numGlyphs from result (offset 4, uint16)
      num_glyphs = result[4, 2].unpack1("n")
      expect(num_glyphs).to eq(mapping.size)
    end

    it "preserves other maxp fields" do
      maxp = font.table("maxp")
      original = maxp.to_binary_s
      result = subsetter.subset_maxp(maxp)

      # Version should be unchanged (first 4 bytes)
      expect(result[0, 4]).to eq(original[0, 4])
    end
  end

  describe "#subset_hhea" do
    it "uses hmtx metrics to update numberOfHMetrics field" do
      hmtx = font.table("hmtx")
      hhea = font.table("hhea")

      # Ensure hmtx is parsed
      unless hmtx.parsed?
        maxp = font.table("maxp")
        hmtx.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)
      end

      result = subsetter.subset_hhea(hhea, hmtx)

      # Parse numberOfHMetrics from result (offset 34, uint16)
      num_h_metrics = result[34, 2].unpack1("n")
      expected_size = hmtx.h_metrics ? hmtx.h_metrics.size : mapping.size
      expect(num_h_metrics).to eq(expected_size)
    end

    it "preserves other hhea fields" do
      hhea = font.table("hhea")
      original = hhea.to_binary_s
      hmtx = font.table("hmtx")
      result = subsetter.subset_hhea(hhea, hmtx)

      # Ascender should be unchanged (offset 4, int16)
      expect(result[4, 2]).to eq(original[4, 2])
    end
  end

  describe "#subset_hmtx" do
    it "builds new hmtx with subset metrics" do
      hmtx = font.table("hmtx")
      result = subsetter.subset_hmtx(hmtx)

      # Should have exactly mapping.size * 4 bytes (advance_width + lsb)
      expect(result.bytesize).to eq(mapping.size * 4)
    end

    it "preserves metrics order according to mapping" do
      hmtx = font.table("hmtx")
      result = subsetter.subset_hmtx(hmtx)

      # First metric should be for glyph 0 (.notdef)
      advance_width = result[0, 2].unpack1("n")
      lsb = result[2, 2].unpack1("n")

      original_metric = hmtx.metric_for(0)
      expect(advance_width).to eq(original_metric[:advance_width])
      expect(lsb).to eq(original_metric[:lsb])
    end
  end

  describe "#subset_glyf and #subset_loca" do
    it "builds glyf and loca tables together" do
      glyf = font.table("glyf")
      loca = font.table("loca")

      glyf_result = subsetter.subset_glyf(glyf)
      loca_result = subsetter.subset_loca(loca)

      expect(glyf_result).to be_a(String)
      expect(loca_result).to be_a(String)
    end

    it "creates loca with correct number of offsets" do
      glyf = font.table("glyf")
      loca = font.table("loca")

      subsetter.subset_glyf(glyf)
      loca_result = subsetter.subset_loca(loca)

      head = font.table("head")
      format = head.index_to_loc_format
      entry_size = format == 0 ? 2 : 4

      # Should have mapping.size + 1 offsets
      expected_entries = mapping.size + 1
      expect(loca_result.bytesize).to eq(expected_entries * entry_size)
    end
  end

  describe "#subset_cmap" do
    it "remaps character to glyph mappings" do
      cmap = font.table("cmap")
      result = subsetter.subset_cmap(cmap)

      expect(result).to be_a(String)
      expect(result.bytesize).to be > 0
    end

    # Note: Comprehensive cmap building is TODO in implementation
  end

  describe "#subset_post" do
    context "with drop_names option" do
      let(:options) { Fontisan::Subset::Options.new(drop_names: true) }

      it "builds post version 3.0" do
        post = font.table("post")
        result = subsetter.subset_post(post)

        # Version should be 3.0 (0x00030000)
        version = result[0, 4].unpack1("N")
        expect(version).to eq(0x00030000)
      end
    end

    context "without drop_names option" do
      it "passes through original post table" do
        post = font.table("post")
        original_data = font.table_data["post"]

        result = subsetter.subset_post(post)
        expect(result).to eq(original_data)
      end
    end
  end

  describe "#subset_head" do
    it "passes through head table unchanged" do
      head = font.table("head")
      original_data = font.table_data["head"]

      result = subsetter.subset_head(head)
      expect(result).to eq(original_data)
    end
  end

  describe "#subset_name" do
    it "passes through name table unchanged" do
      name = font.table("name")
      original_data = font.table_data["name"]

      result = subsetter.subset_name(name)
      expect(result).to eq(original_data)
    end
  end

  describe "#subset_os2" do
    it "passes through OS/2 table" do
      os2 = font.table("OS/2")
      original_data = font.table_data["OS/2"]

      result = subsetter.subset_os2(os2)
      expect(result).to eq(original_data)
    end

    # Note: Unicode range pruning is TODO in implementation
  end

  describe "private methods" do
    describe "#compound_glyph?" do
      it "identifies compound glyphs" do
        # Create mock compound glyph data (numberOfContours = -1)
        compound_data = [0xFFFF].pack("n") + ("x" * 10)
        expect(subsetter.send(:compound_glyph?, compound_data)).to be true
      end

      it "identifies simple glyphs" do
        # Create mock simple glyph data (numberOfContours = 2)
        simple_data = [2].pack("n") + ("x" * 10)
        expect(subsetter.send(:compound_glyph?, simple_data)).to be false
      end

      it "handles empty data" do
        expect(subsetter.send(:compound_glyph?, "")).to be false
      end
    end
  end

  describe "error handling" do
    it "handles missing component glyphs in compound glyph remapping" do
      # Create a mapping that doesn't include all components
      partial_mapping = Fontisan::Subset::GlyphMapping.new([0, 1],
                                                           retain_gids: false)
      partial_subsetter = described_class.new(font, partial_mapping, options)

      # Try to remap a compound glyph that references missing components
      compound_data = [0xFFFF].pack("n") + ("x" * 8)
      compound_data << [0x0020].pack("n") # flags (MORE_COMPONENTS not set)
      compound_data << [100].pack("n")     # glyph_index not in mapping
      compound_data << [0, 0].pack("n2")   # args

      expect do
        partial_subsetter.send(:remap_compound_glyph, compound_data)
      end.to raise_error(Fontisan::SubsettingError, /not in subset/)
    end
  end
end
