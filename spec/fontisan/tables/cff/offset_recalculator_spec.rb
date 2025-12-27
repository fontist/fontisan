# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff/offset_recalculator"

RSpec.describe Fontisan::Tables::Cff::OffsetRecalculator do
  let(:sections) do
    {
      header: "HEAD".b,
      name_index: "NAME".b,
      top_dict_index: "TOPD".b,
      string_index: "STRS".b,
      global_subr_index: "GSUB".b,
      charstrings_index: "CHRS".b,
      private_dict: "PRIV".b,
    }
  end

  describe ".calculate_offsets" do
    it "calculates charstrings offset correctly" do
      offsets = described_class.calculate_offsets(sections)
      # Header(4) + Name(4) + TopDict(4) + String(4) + GlobalSubr(4) = 20
      expect(offsets[:charstrings]).to eq(20)
    end

    it "calculates private dict offset correctly" do
      offsets = described_class.calculate_offsets(sections)
      # Header(4) + Name(4) + TopDict(4) + String(4) + GlobalSubr(4) + CharStrings(4) = 24
      expect(offsets[:private]).to eq(24)
    end

    it "calculates private dict size correctly" do
      offsets = described_class.calculate_offsets(sections)
      expect(offsets[:private_size]).to eq(4)
    end

    it "calculates top_dict_start offset" do
      offsets = described_class.calculate_offsets(sections)
      # Header(4) + Name(4) = 8
      expect(offsets[:top_dict_start]).to eq(8)
    end

    it "handles larger sections" do
      large_sections = {
        header: "H" * 100,
        name_index: "N" * 200,
        top_dict_index: "T" * 150,
        string_index: "S" * 300,
        global_subr_index: "G" * 250,
        charstrings_index: "C" * 500,
        private_dict: "P" * 400,
      }

      offsets = described_class.calculate_offsets(large_sections)
      expected_charstrings = 100 + 200 + 150 + 300 + 250
      expect(offsets[:charstrings]).to eq(expected_charstrings)
    end

    it "handles empty private dict" do
      empty_sections = sections.merge(private_dict: "".b)
      offsets = described_class.calculate_offsets(empty_sections)
      expect(offsets[:private_size]).to eq(0)
    end

    it "handles empty global subr index" do
      empty_sections = sections.merge(global_subr_index: "".b)
      offsets = described_class.calculate_offsets(empty_sections)
      # CharStrings offset should be reduced by GlobalSubr size
      expect(offsets[:charstrings]).to eq(16)
    end

    it "returns hash with all required keys" do
      offsets = described_class.calculate_offsets(sections)
      expect(offsets.keys).to include(:top_dict_start, :charstrings, :private, :private_size)
    end

    it "offsets increase sequentially" do
      offsets = described_class.calculate_offsets(sections)
      expect(offsets[:top_dict_start]).to be < offsets[:charstrings]
      expect(offsets[:charstrings]).to be < offsets[:private]
    end

    it "handles varied section sizes" do
      varied = {
        header: "H".b,
        name_index: "NN".b,
        top_dict_index: "TTT".b,
        string_index: "SSSS".b,
        global_subr_index: "GGGGG".b,
        charstrings_index: "CCCCCC".b,
        private_dict: "PPPPPPP".b,
      }

      offsets = described_class.calculate_offsets(varied)
      # 1+2+3+4+5 = 15
      expect(offsets[:charstrings]).to eq(15)
      # 1+2+3+4+5+6 = 21
      expect(offsets[:private]).to eq(21)
      expect(offsets[:private_size]).to eq(7)
    end
  end

  describe ".update_top_dict" do
    let(:top_dict) do
      {
        version: 391,
        notice: 392,
        charstrings: 1000,
        private: [50, 1500],
      }
    end

    let(:offsets) do
      {
        charstrings: 2000,
        private: 3000,
        private_size: 100,
      }
    end

    it "updates charstrings offset" do
      updated = described_class.update_top_dict(top_dict, offsets)
      expect(updated[:charstrings]).to eq(2000)
    end

    it "updates private offset and size" do
      updated = described_class.update_top_dict(top_dict, offsets)
      expect(updated[:private]).to eq([100, 3000])
    end

    it "preserves other top dict values" do
      updated = described_class.update_top_dict(top_dict, offsets)
      expect(updated[:version]).to eq(391)
      expect(updated[:notice]).to eq(392)
    end

    it "does not modify original dict" do
      original_charstrings = top_dict[:charstrings]
      original_private = top_dict[:private].dup

      described_class.update_top_dict(top_dict, offsets)

      expect(top_dict[:charstrings]).to eq(original_charstrings)
      expect(top_dict[:private]).to eq(original_private)
    end

    it "handles empty top dict" do
      empty_dict = {}
      updated = described_class.update_top_dict(empty_dict, offsets)
      expect(updated[:charstrings]).to eq(2000)
      expect(updated[:private]).to eq([100, 3000])
    end

    it "handles zero offsets" do
      zero_offsets = { charstrings: 0, private: 0, private_size: 0 }
      updated = described_class.update_top_dict(top_dict, zero_offsets)
      expect(updated[:charstrings]).to eq(0)
      expect(updated[:private]).to eq([0, 0])
    end
  end

  describe "integration" do
    it "calculate and update work together" do
      offsets = described_class.calculate_offsets(sections)
      top_dict = { version: 391 }
      updated = described_class.update_top_dict(top_dict, offsets)

      expect(updated[:charstrings]).to eq(offsets[:charstrings])
      expect(updated[:private]).to eq([offsets[:private_size], offsets[:private]])
    end

    it "handles modified private dict size" do
      # Start with small private dict
      small_sections = sections.merge(private_dict: "PP".b)
      offsets1 = described_class.calculate_offsets(small_sections)

      # Increase private dict size
      large_sections = sections.merge(private_dict: "P" * 100)
      offsets2 = described_class.calculate_offsets(large_sections)

      # Private offset should be same, but size different
      expect(offsets2[:private]).to eq(offsets1[:private])
      expect(offsets2[:private_size]).to be > offsets1[:private_size]
    end
  end
end