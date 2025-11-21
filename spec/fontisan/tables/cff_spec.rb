# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff do
  describe "basic CFF table" do
    let(:cff_data) do
      # Build a minimal valid CFF table structure
      parts = []

      # Header: major=1, minor=0, hdr_size=4, off_size=1
      parts << [0x01, 0x00, 0x04, 0x01].pack("C4")

      # Name INDEX: 1 font named "TestFont"
      parts << [1].pack("n")                    # count
      parts << [1].pack("C")                    # offSize
      parts << [1, 9].pack("C2")                # offsets [1, 9]
      parts << "TestFont"                       # data (8 bytes)

      # Top DICT INDEX: 1 DICT (empty for this test)
      parts << [1].pack("n")                    # count
      parts << [1].pack("C")                    # offSize
      parts << [1, 1].pack("C2")                # offsets [1, 1] (empty)
      # No data (empty DICT)

      # String INDEX: empty
      parts << [0].pack("n") # count

      # Global Subr INDEX: empty
      parts << [0].pack("n") # count

      parts.join
    end

    let(:cff) { described_class.read(cff_data) }

    it "parses header correctly" do
      expect(cff.header).to be_a(Fontisan::Tables::Cff::Header)
      expect(cff.header.major).to eq(1)
      expect(cff.header.minor).to eq(0)
    end

    it "parses name index correctly" do
      expect(cff.name_index).to be_a(Fontisan::Tables::Cff::Index)
      expect(cff.name_index.count).to eq(1)
    end

    it "parses top dict index correctly" do
      expect(cff.top_dict_index).to be_a(Fontisan::Tables::Cff::Index)
      expect(cff.top_dict_index.count).to eq(1)
    end

    it "parses string index correctly" do
      expect(cff.string_index).to be_a(Fontisan::Tables::Cff::Index)
      expect(cff.string_index.count).to eq(0)
    end

    it "parses global subr index correctly" do
      expect(cff.global_subr_index).to be_a(Fontisan::Tables::Cff::Index)
      expect(cff.global_subr_index.count).to eq(0)
    end

    it "returns correct font count" do
      expect(cff.font_count).to eq(1)
    end

    it "returns correct font name" do
      expect(cff.font_name(0)).to eq("TestFont")
    end

    it "returns all font names" do
      expect(cff.font_names).to eq(["TestFont"])
    end

    it "identifies as CFF version 1" do
      expect(cff.cff?).to be true
      expect(cff.cff2?).to be false
    end

    it "returns correct version" do
      expect(cff.version).to eq("1.0")
    end

    it "is valid" do
      expect(cff.valid?).to be true
    end

    it "has correct custom string count" do
      expect(cff.custom_string_count).to eq(0)
    end

    it "has correct global subr count" do
      expect(cff.global_subr_count).to eq(0)
    end
  end

  describe "CFF table with multiple fonts" do
    let(:cff_data) do
      parts = []

      # Header
      parts << [0x01, 0x00, 0x04, 0x01].pack("C4")

      # Name INDEX: 2 fonts
      parts << [2].pack("n")                         # count
      parts << [1].pack("C")                         # offSize
      parts << [1, 6, 11].pack("C3")                 # offsets
      parts << "Font1Font2" # data

      # Top DICT INDEX: 2 DICTs (both empty)
      parts << [2].pack("n")                         # count
      parts << [1].pack("C")                         # offSize
      parts << [1, 1, 1].pack("C3")                  # offsets
      # No data

      # String INDEX: empty
      parts << [0].pack("n")

      # Global Subr INDEX: empty
      parts << [0].pack("n")

      parts.join
    end

    let(:cff) { described_class.read(cff_data) }

    it "returns correct font count" do
      expect(cff.font_count).to eq(2)
    end

    it "returns correct font names" do
      expect(cff.font_name(0)).to eq("Font1")
      expect(cff.font_name(1)).to eq("Font2")
      expect(cff.font_names).to eq(["Font1", "Font2"])
    end

    it "returns nil for invalid font index" do
      expect(cff.font_name(2)).to be_nil
      expect(cff.font_name(-1)).to be_nil
    end
  end

  describe "CFF table with custom strings" do
    let(:cff_data) do
      parts = []

      # Header
      parts << [0x01, 0x00, 0x04, 0x01].pack("C4")

      # Name INDEX
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 5].pack("C2")
      parts << "Font"

      # Top DICT INDEX
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 1].pack("C2")

      # String INDEX: 2 custom strings
      parts << [2].pack("n")                             # count
      parts << [1].pack("C")                             # offSize
      parts << [1, 8, 15].pack("C3")                     # offsets
      parts << "Custom1Custom2" # data

      # Global Subr INDEX: empty
      parts << [0].pack("n")

      parts.join
    end

    let(:cff) { described_class.read(cff_data) }

    it "returns correct custom string count" do
      expect(cff.custom_string_count).to eq(2)
    end

    it "returns standard string for low SID" do
      # SID 0 is ".notdef"
      expect(cff.string_for_sid(0)).to eq(".notdef")
      # SID 1 is "space"
      expect(cff.string_for_sid(1)).to eq("space")
    end

    it "returns custom string for high SID" do
      # SID 391 is first custom string (391 - 391 = 0)
      expect(cff.string_for_sid(391)).to eq("Custom1")
      expect(cff.string_for_sid(392)).to eq("Custom2")
    end

    it "returns nil for invalid SID" do
      expect(cff.string_for_sid(393)).to be_nil
    end
  end

  describe "CFF table with global subroutines" do
    let(:cff_data) do
      parts = []

      # Header
      parts << [0x01, 0x00, 0x04, 0x01].pack("C4")

      # Name INDEX
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 5].pack("C2")
      parts << "Font"

      # Top DICT INDEX
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 1].pack("C2")

      # String INDEX: empty
      parts << [0].pack("n")

      # Global Subr INDEX: 3 subroutines
      parts << [3].pack("n")                             # count
      parts << [1].pack("C")                             # offSize
      parts << [1, 4, 7, 10].pack("C4")                  # offsets
      parts << "ABCDEFGHI" # data

      parts.join
    end

    let(:cff) { described_class.read(cff_data) }

    it "returns correct global subr count" do
      expect(cff.global_subr_count).to eq(3)
    end

    it "provides access to global subroutines via index" do
      expect(cff.global_subr_index[0]).to eq("ABC")
      expect(cff.global_subr_index[1]).to eq("DEF")
      expect(cff.global_subr_index[2]).to eq("GHI")
    end
  end

  describe "CFF2 table" do
    let(:cff_data) do
      parts = []

      # Header: major=2, minor=0, hdr_size=5, off_size=1, top_dict_size=0
      parts << [0x02, 0x00, 0x05, 0x01, 0x00].pack("C5")

      # Name INDEX
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 5].pack("C2")
      parts << "Font"

      # Top DICT INDEX
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 1].pack("C2")

      # String INDEX: empty
      parts << [0].pack("n")

      # Global Subr INDEX: empty
      parts << [0].pack("n")

      parts.join
    end

    let(:cff) { described_class.read(cff_data) }

    it "identifies as CFF2" do
      expect(cff.cff2?).to be true
      expect(cff.cff?).to be false
    end

    it "returns correct version" do
      expect(cff.version).to eq("2.0")
    end
  end

  describe "validation" do
    it "rejects CFF with zero fonts" do
      parts = []
      parts << [0x01, 0x00, 0x04, 0x01].pack("C4")  # Header
      parts << [0].pack("n")                        # Name INDEX: count=0

      expect do
        described_class.read(parts.join)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /must contain at least one font/)
    end

    it "rejects CFF with mismatched name and top DICT counts" do
      parts = []
      parts << [0x01, 0x00, 0x04, 0x01].pack("C4")  # Header

      # Name INDEX: 1 font
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 5].pack("C2")
      parts << "Font"

      # Top DICT INDEX: 2 DICTs (mismatch!)
      parts << [2].pack("n")
      parts << [1].pack("C")
      parts << [1, 1, 1].pack("C3")

      expect do
        described_class.read(parts.join)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Top DICT count.*must match Name count/)
    end

    it "rejects invalid header" do
      # Invalid major version
      data = [0x03, 0x00, 0x04, 0x01].pack("C4")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Invalid CFF header/)
    end
  end

  describe "error handling" do
    it "wraps parsing errors in CorruptedTableError" do
      # Truncated data
      data = [0x01, 0x00].pack("C2")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Failed to parse CFF table/)
    end

    it "handles empty data gracefully" do
      expect do
        described_class.read("")
      end.to raise_error(Fontisan::CorruptedTableError)
    end

    it "handles nil data gracefully" do
      cff = described_class.read(nil)
      expect(cff.font_count).to eq(0)
      expect(cff.valid?).to be false
    end
  end

  describe "extended header" do
    let(:cff_data) do
      parts = []

      # Header with hdr_size=6 (2 extra reserved bytes)
      parts << [0x01, 0x00, 0x06, 0x01, 0x00, 0x00].pack("C6")

      # Name INDEX
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 5].pack("C2")
      parts << "Font"

      # Top DICT INDEX
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 1].pack("C2")

      # String INDEX: empty
      parts << [0].pack("n")

      # Global Subr INDEX: empty
      parts << [0].pack("n")

      parts.join
    end

    let(:cff) { described_class.read(cff_data) }

    it "handles extended header size" do
      expect(cff.header.hdr_size).to eq(6)
      expect(cff.valid?).to be true
    end

    it "parses remaining structures correctly" do
      expect(cff.font_count).to eq(1)
      expect(cff.font_name(0)).to eq("Font")
    end
  end

  describe "table tag" do
    it "has correct TAG constant" do
      expect(described_class::TAG).to eq("CFF ")
    end
  end
end
