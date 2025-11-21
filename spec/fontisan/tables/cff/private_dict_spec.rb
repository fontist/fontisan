# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff::PrivateDict do
  describe "Private DICT specific operators" do
    it "parses blue_values operator" do
      # blue_values (operator 6) - array of alignment zone pairs
      data = [251, 143, 251, 135, 247, 24, 247, 36, 6].pack("C*")
      # Values: -251, -243, 132, 144 (bottom/top pairs for alignment zones)
      dict = described_class.new(data)
      expect(dict[:blue_values]).to be_an(Array)
      expect(dict.blue_values).to eq(dict[:blue_values])
    end

    it "parses other_blues operator" do
      # other_blues (operator 7)
      data = [251, 200, 251, 180, 7].pack("CCCCC")
      dict = described_class.new(data)
      expect(dict[:other_blues]).to be_an(Array)
      expect(dict.other_blues).to eq(dict[:other_blues])
    end

    it "parses family_blues operator" do
      # family_blues (operator 8)
      data = [251, 143, 251, 135, 8].pack("CCCCC")
      dict = described_class.new(data)
      expect(dict[:family_blues]).to be_an(Array)
      expect(dict.family_blues).to eq(dict[:family_blues])
    end

    it "parses family_other_blues operator" do
      # family_other_blues (operator 9)
      data = [251, 200, 251, 180, 9].pack("CCCCC")
      dict = described_class.new(data)
      expect(dict[:family_other_blues]).to be_an(Array)
      expect(dict.family_other_blues).to eq(dict[:family_other_blues])
    end

    it "parses std_hw operator (standard horizontal width)" do
      # std_hw (operator 10) - stored as single-element array
      data = [189, 10].pack("CC") # value 50 (189 = 50 + 139)
      dict = described_class.new(data)
      expect(dict[:std_hw]).to eq(50)
      expect(dict.std_hw).to eq(50)
    end

    it "parses std_vw operator (standard vertical width)" do
      # std_vw (operator 11) - stored as single-element array
      data = [204, 11].pack("CC") # value 65 (204 = 65 + 139)
      dict = described_class.new(data)
      expect(dict[:std_vw]).to eq(65)
      expect(dict.std_vw).to eq(65)
    end

    it "parses stem_snap_h operator" do
      # stem_snap_h (operator [12, 12]) - array of horizontal stem widths
      data = [189, 199, 209, 12, 12].pack("CCCCC") # [50, 60, 70] (189=50+139, 199=60+139, 209=70+139)
      dict = described_class.new(data)
      expect(dict[:stem_snap_h]).to be_an(Array)
      expect(dict.stem_snap_h).to eq(dict[:stem_snap_h])
    end

    it "parses stem_snap_v operator" do
      # stem_snap_v (operator [12, 13]) - array of vertical stem widths
      data = [204, 214, 224, 12, 13].pack("CCCCC") # [65, 75, 85] (204=65+139, 214=75+139, 224=85+139)
      dict = described_class.new(data)
      expect(dict[:stem_snap_v]).to be_an(Array)
      expect(dict.stem_snap_v).to eq(dict[:stem_snap_v])
    end

    it "parses subrs operator (Local Subr offset)" do
      # subrs (operator 19)
      data = [28, 0x01, 0xF4, 19].pack("CCCC") # offset 500
      dict = described_class.new(data)
      expect(dict[:subrs]).to eq(500)
      expect(dict.subrs).to eq(500)
    end

    it "parses default_width_x operator" do
      # default_width_x (operator 20)
      data = [28, 0x02, 0x00, 20].pack("CCCC") # width 512
      dict = described_class.new(data)
      expect(dict[:default_width_x]).to eq(512)
      expect(dict.default_width_x).to eq(512)
    end

    it "parses nominal_width_x operator" do
      # nominal_width_x (operator 21)
      data = [28, 0x01, 0xF4, 21].pack("CCCC") # width 500
      dict = described_class.new(data)
      expect(dict[:nominal_width_x]).to eq(500)
      expect(dict.nominal_width_x).to eq(500)
    end

    it "parses blue_scale operator" do
      # blue_scale (operator [12, 9]) - real number
      data = [30, 0x0a, 0x03, 0x96, 0x25, 0xff, 12, 9].pack("C*")
      # Real: 0.039625 (nibbles: 0, a(.), 0, 3, 9, 6, 2, 5, f, f)
      dict = described_class.new(data)
      expect(dict[:blue_scale]).to be_within(0.0001).of(0.039625)
      expect(dict.blue_scale).to be_within(0.0001).of(0.039625)
    end

    it "parses blue_shift operator" do
      # blue_shift (operator [12, 10])
      data = [146, 12, 10].pack("CCC") # value 7
      dict = described_class.new(data)
      expect(dict[:blue_shift]).to eq(7)
      expect(dict.blue_shift).to eq(7)
    end

    it "parses blue_fuzz operator" do
      # blue_fuzz (operator [12, 11])
      data = [140, 12, 11].pack("CCC") # value 1
      dict = described_class.new(data)
      expect(dict[:blue_fuzz]).to eq(1)
      expect(dict.blue_fuzz).to eq(1)
    end

    it "parses force_bold operator" do
      # force_bold (operator [12, 14]) - boolean (0 or 1)
      data = [140, 12, 14].pack("CCC") # value 1 (true)
      dict = described_class.new(data)
      expect(dict[:force_bold]).to eq(1)
      expect(dict.force_bold?).to eq(1) # Truthy
    end

    it "parses language_group operator" do
      # language_group (operator [12, 17]) - 0=Latin, 1=CJK
      data = [140, 12, 17].pack("CCC") # value 1 (CJK)
      dict = described_class.new(data)
      expect(dict[:language_group]).to eq(1)
      expect(dict.language_group).to eq(1)
      expect(dict.cjk?).to be true
    end

    it "parses expansion_factor operator" do
      # expansion_factor (operator [12, 18]) - real number
      data = [30, 0x0a, 0x06, 0xff, 12, 18].pack("C*")
      # Real: 0.06 (nibbles: 0, a(.), 0, 6, f, f)
      dict = described_class.new(data)
      expect(dict[:expansion_factor]).to be_within(0.001).of(0.06)
      expect(dict.expansion_factor).to be_within(0.001).of(0.06)
    end

    it "parses initial_random_seed operator" do
      # initial_random_seed (operator [12, 19])
      data = [139, 12, 19].pack("CCC") # value 0
      dict = described_class.new(data)
      expect(dict[:initial_random_seed]).to eq(0)
      expect(dict.initial_random_seed).to eq(0)
    end
  end

  describe "default values" do
    let(:empty_dict) { described_class.new("") }

    it "provides default for blue_scale" do
      expect(empty_dict.blue_scale).to be_within(0.0001).of(0.039625)
    end

    it "provides default for blue_shift" do
      expect(empty_dict.blue_shift).to eq(7)
    end

    it "provides default for blue_fuzz" do
      expect(empty_dict.blue_fuzz).to eq(1)
    end

    it "provides default for force_bold" do
      expect(empty_dict.force_bold?).to be false
    end

    it "provides default for language_group" do
      expect(empty_dict.language_group).to eq(0) # Latin
    end

    it "provides default for expansion_factor" do
      expect(empty_dict.expansion_factor).to be_within(0.001).of(0.06)
    end

    it "provides default for initial_random_seed" do
      expect(empty_dict.initial_random_seed).to eq(0)
    end

    it "provides default for default_width_x" do
      expect(empty_dict.default_width_x).to eq(0)
    end

    it "provides default for nominal_width_x" do
      expect(empty_dict.nominal_width_x).to eq(0)
    end
  end

  describe "#fetch" do
    it "returns value if present" do
      data = [146, 12, 10].pack("CCC") # blue_shift = 7
      dict = described_class.new(data)
      expect(dict.fetch(:blue_shift)).to eq(7)
    end

    it "returns default if not present" do
      dict = described_class.new("")
      expect(dict.fetch(:blue_shift)).to eq(7)
    end

    it "returns provided default if key has no default" do
      dict = described_class.new("")
      expect(dict.fetch(:blue_values, [])).to eq([])
    end
  end

  describe "helper methods" do
    describe "#has_local_subrs?" do
      it "returns true when subrs is present" do
        data = [28, 0x01, 0xF4, 19].pack("CCCC") # subrs = 500
        dict = described_class.new(data)
        expect(dict.has_local_subrs?).to be true
      end

      it "returns false when subrs is absent" do
        dict = described_class.new("")
        expect(dict.has_local_subrs?).to be false
      end
    end

    describe "#has_blue_values?" do
      it "returns true when blue_values is present and not empty" do
        data = [251, 143, 251, 135, 6].pack("CCCCC")
        dict = described_class.new(data)
        expect(dict.has_blue_values?).to be true
      end

      it "returns false when blue_values is absent" do
        dict = described_class.new("")
        expect(dict.has_blue_values?).to be false
      end
    end

    describe "#cjk?" do
      it "returns true for CJK language group" do
        data = [140, 12, 17].pack("CCC") # language_group = 1
        dict = described_class.new(data)
        expect(dict.cjk?).to be true
      end

      it "returns false for Latin language group" do
        data = [139, 12, 17].pack("CCC") # language_group = 0
        dict = described_class.new(data)
        expect(dict.cjk?).to be false
      end

      it "returns false for default language group" do
        dict = described_class.new("")
        expect(dict.cjk?).to be false
      end
    end
  end

  describe "std_hw and std_vw handling" do
    it "handles std_hw as array with single element" do
      # When parsed with array, extract first element
      data = [189, 10].pack("CC") # std_hw = 50 (189 = 50 + 139)
      dict = described_class.new(data)
      expect(dict.std_hw).to eq(50)
    end

    it "handles std_vw as array with single element" do
      data = [204, 11].pack("CC") # std_vw = 65 (204 = 65 + 139)
      dict = described_class.new(data)
      expect(dict.std_vw).to eq(65)
    end
  end

  describe "complex Private DICT" do
    it "parses multiple operators" do
      # Build a complex Private DICT
      data = [
        251, 143, 251, 135, 6, # blue_values = [-251, -243]
        189, 10,                   # std_hw = 50 (189 = 50 + 139)
        204, 11,                   # std_vw = 65 (204 = 65 + 139)
        28, 0x01, 0xF4, 19,       # subrs = 500
        28, 0x02, 0x00, 20,       # default_width_x = 512
        28, 0x01, 0xF4, 21 # nominal_width_x = 500
      ].pack("C*")

      dict = described_class.new(data)
      expect(dict.blue_values).to be_an(Array)
      expect(dict.std_hw).to eq(50)
      expect(dict.std_vw).to eq(65)
      expect(dict.subrs).to eq(500)
      expect(dict.default_width_x).to eq(512)
      expect(dict.nominal_width_x).to eq(500)
      expect(dict.has_local_subrs?).to be true
      expect(dict.has_blue_values?).to be true
    end
  end
end
