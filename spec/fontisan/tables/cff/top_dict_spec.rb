# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff::TopDict do
  describe "Top DICT specific operators" do
    it "parses charset operator" do
      # charset (operator 15) with offset 1000
      data = [28, 0x03, 0xE8, 15].pack("CCCC") # 3-byte int 1000, operator 15
      dict = described_class.new(data)
      expect(dict[:charset]).to eq(1000)
      expect(dict.charset).to eq(1000)
    end

    it "parses encoding operator" do
      # encoding (operator 16) with offset 500
      data = [28, 0x01, 0xF4, 16].pack("CCCC") # 3-byte int 500, operator 16
      dict = described_class.new(data)
      expect(dict[:encoding]).to eq(500)
      expect(dict.encoding).to eq(500)
    end

    it "parses charstrings operator" do
      # charstrings (operator 17) with offset 2000
      data = [28, 0x07, 0xD0, 17].pack("CCCC") # 3-byte int 2000, operator 17
      dict = described_class.new(data)
      expect(dict[:charstrings]).to eq(2000)
      expect(dict.charstrings).to eq(2000)
    end

    it "parses private operator (two operands: size and offset)" do
      # private (operator 18) with size=100, offset=3000
      data = [239, 28, 0x0B, 0xB8, 18].pack("CCCCC") # 100, 3000, operator 18
      dict = described_class.new(data)
      expect(dict[:private]).to eq([100, 3000])
      expect(dict.private_size).to eq(100)
      expect(dict.private_offset).to eq(3000)
    end

    it "parses font_bbox operator (four operands)" do
      # font_bbox (operator 5) with [xMin, yMin, xMax, yMax]
      # Values: -100, -200, 1000, 2000
      data = [251, 100, # -208 + 100 = -100 (using 251 encoding)
              251, 200, # -308 + 100 = -200
              28, 0x03, 0xE8, # 1000
              28, 0x07, 0xD0, # 2000
              5].pack("C*")
      dict = described_class.new(data)
      bbox = dict[:font_bbox]
      expect(bbox).to be_an(Array)
      expect(bbox.size).to eq(4)
      expect(dict.font_bbox).to eq(bbox)
    end

    it "parses unique_id operator" do
      # unique_id (operator 13)
      data = [29, 0x00, 0x00, 0x27, 0x10, 13].pack("CCCCCC") # 10000, operator 13
      dict = described_class.new(data)
      expect(dict[:unique_id]).to eq(10000)
    end

    it "parses two-byte Top DICT operators" do
      # ros (operator [12, 30]) for CIDFonts: [registry, ordering, supplement]
      data = [239, 239, 139, 12, 30].pack("CCCCC") # [100, 100, 0], operator [12,30]
      dict = described_class.new(data)
      expect(dict[:ros]).to eq([100, 100, 0])
      expect(dict.ros).to eq([100, 100, 0])
    end

    it "parses cid_count operator" do
      # cid_count (operator [12, 34])
      data = [28, 0x22, 0x10, 12, 34].pack("CCCCC") # 8720, operator [12, 34]
      dict = described_class.new(data)
      expect(dict[:cid_count]).to eq(8720)
      expect(dict.cid_count).to eq(8720)
    end

    it "parses fd_array operator" do
      # fd_array (operator [12, 36])
      data = [28, 0x0F, 0xA0, 12, 36].pack("CCCCC") # 4000, operator [12, 36]
      dict = described_class.new(data)
      expect(dict[:fd_array]).to eq(4000)
      expect(dict.fd_array).to eq(4000)
    end

    it "parses fd_select operator" do
      # fd_select (operator [12, 37])
      data = [28, 0x13, 0x88, 12, 37].pack("CCCCC") # 5000, operator [12, 37]
      dict = described_class.new(data)
      expect(dict[:fd_select]).to eq(5000)
      expect(dict.fd_select).to eq(5000)
    end
  end

  describe "default values" do
    let(:empty_dict) { described_class.new("") }

    it "provides default for charset" do
      expect(empty_dict.charset).to eq(0) # ISOAdobe charset
    end

    it "provides default for encoding" do
      expect(empty_dict.encoding).to eq(0) # Standard encoding
    end

    it "provides default for font_bbox" do
      expect(empty_dict.font_bbox).to eq([0, 0, 0, 0])
    end

    it "provides default for font_matrix" do
      expect(empty_dict.font_matrix).to eq([0.001, 0, 0, 0.001, 0, 0])
    end

    it "provides default for charstring_type" do
      expect(empty_dict.charstring_type).to eq(2)
    end

    it "provides default for cid_count" do
      expect(empty_dict.cid_count).to eq(8720)
    end
  end

  describe "#fetch" do
    it "returns value if present" do
      data = [28, 0x03, 0xE8, 15].pack("CCCC") # charset = 1000
      dict = described_class.new(data)
      expect(dict.fetch(:charset)).to eq(1000)
    end

    it "returns default if not present" do
      dict = described_class.new("")
      expect(dict.fetch(:charset)).to eq(0)
    end

    it "returns provided default if key has no default" do
      dict = described_class.new("")
      expect(dict.fetch(:charstrings, 999)).to eq(999)
    end
  end

  describe "CIDFont detection" do
    it "detects CIDFont by presence of ROS" do
      # ROS present
      data = [139, 139, 139, 12, 30].pack("CCCCC") # [0, 0, 0], operator [12, 30]
      dict = described_class.new(data)
      expect(dict.cid_font?).to be true
    end

    it "detects non-CIDFont by absence of ROS" do
      dict = described_class.new("")
      expect(dict.cid_font?).to be false
    end
  end

  describe "charset type detection" do
    it "detects predefined charsets" do
      # ISOAdobe charset (0)
      data = [139, 15].pack("CC") # 0, operator 15
      dict = described_class.new(data)
      expect(dict.custom_charset?).to be false

      # Expert charset (1)
      data = [140, 15].pack("CC") # 1, operator 15
      dict = described_class.new(data)
      expect(dict.custom_charset?).to be false

      # Expert Subset charset (2)
      data = [141, 15].pack("CC") # 2, operator 15
      dict = described_class.new(data)
      expect(dict.custom_charset?).to be false
    end

    it "detects custom charset" do
      # Custom charset (offset 1000)
      data = [28, 0x03, 0xE8, 15].pack("CCCC") # 1000, operator 15
      dict = described_class.new(data)
      expect(dict.custom_charset?).to be true
    end
  end

  describe "encoding type detection" do
    it "detects predefined encodings" do
      # Standard encoding (0)
      data = [139, 16].pack("CC") # 0, operator 16
      dict = described_class.new(data)
      expect(dict.custom_encoding?).to be false

      # Expert encoding (1)
      data = [140, 16].pack("CC") # 1, operator 16
      dict = described_class.new(data)
      expect(dict.custom_encoding?).to be false
    end

    it "detects custom encoding" do
      # Custom encoding (offset 500)
      data = [28, 0x01, 0xF4, 16].pack("CCCC") # 500, operator 16
      dict = described_class.new(data)
      expect(dict.custom_encoding?).to be true
    end
  end

  describe "private DICT accessors" do
    it "extracts private size and offset" do
      # private with size=150, offset=4000
      data = [247, 42, 28, 0x0F, 0xA0, 18].pack("CCCCCC") # 150, 4000, operator 18
      dict = described_class.new(data)
      expect(dict.private).to eq([150, 4000])
      expect(dict.private_size).to eq(150)
      expect(dict.private_offset).to eq(4000)
    end

    it "handles missing private DICT" do
      dict = described_class.new("")
      expect(dict.private).to be_nil
      expect(dict.private_size).to be_nil
      expect(dict.private_offset).to be_nil
    end
  end

  describe "complex Top DICT" do
    it "parses multiple operators" do
      # Build a more complex Top DICT with multiple operators
      data = [
        239, 0, # version = 100
        28, 0x03, 0xE8, 15,      # charset = 1000
        28, 0x01, 0xF4, 16,      # encoding = 500
        28, 0x07, 0xD0, 17,      # charstrings = 2000
        189, 28, 0x0B, 0xB8, 18 # private = [50, 3000] (189 = 50+139)
      ].pack("C*")

      dict = described_class.new(data)
      expect(dict[:version]).to eq(100)
      expect(dict.charset).to eq(1000)
      expect(dict.encoding).to eq(500)
      expect(dict.charstrings).to eq(2000)
      expect(dict.private_size).to eq(50)
      expect(dict.private_offset).to eq(3000)
    end
  end
end
