# frozen_string_literal: true

RSpec.describe Fontisan::Type1::PrivateDict do
  describe "#initialize" do
    it "creates a new PrivateDict with defaults" do
      priv = described_class.new

      expect(priv.blue_values).to eq([])
      expect(priv.other_blues).to eq([])
      expect(priv.blue_scale).to eq(0.039625)
      expect(priv.blue_shift).to eq(7)
      expect(priv.blue_fuzz).to eq(1)
      expect(priv.len_iv).to eq(4)
      expect(priv.force_bold).to be_falsey
    end
  end

  describe ".parse" do
    it "parses BlueValues array" do
      data = <<~DATA
        /Private 10 dict def
          /BlueValues [-10 0 470 480] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.blue_values).to eq([-10, 0, 470, 480])
    end

    it "parses OtherBlues array" do
      data = <<~DATA
        /Private 10 dict def
          /OtherBlues [-250 -240] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.other_blues).to eq([-250, -240])
    end

    it "parses BlueScale" do
      data = <<~DATA
        /Private 10 dict def
          /BlueScale 0.05 def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.blue_scale).to eq(0.05)
    end

    it "defaults BlueScale if not found" do
      data = "/Private 10 dict def end"
      priv = described_class.new.parse(data)

      expect(priv.blue_scale).to eq(0.039625)
    end

    it "parses BlueShift" do
      data = <<~DATA
        /Private 10 dict def
          /BlueShift 8 def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.blue_shift).to eq(8)
    end

    it "parses BlueFuzz" do
      data = <<~DATA
        /Private 10 dict def
          /BlueFuzz 2 def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.blue_fuzz).to eq(2)
    end

    it "parses StdHW array" do
      data = <<~DATA
        /Private 10 dict def
          /StdHW [50] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.std_hw).to eq([50.0])
    end

    it "parses StdVW array" do
      data = <<~DATA
        /Private 10 dict def
          /StdVW [60] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.std_vw).to eq([60.0])
    end

    it "parses StemSnapH array" do
      data = <<~DATA
        /Private 10 dict def
          /StemSnapH [45 50 55] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.stem_snap_h).to eq([45.0, 50.0, 55.0])
    end

    it "parses StemSnapV array" do
      data = <<~DATA
        /Private 10 dict def
          /StemSnapV [55 60 65] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.stem_snap_v).to eq([55.0, 60.0, 65.0])
    end

    it "parses ForceBold" do
      data = <<~DATA
        /Private 10 dict def
          /ForceBold true def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.force_bold).to be true
    end

    it "parses ForceBold as false" do
      data = <<~DATA
        /Private 10 dict def
          /ForceBold false def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.force_bold).to be false
    end

    it "parses lenIV" do
      data = <<~DATA
        /Private 10 dict def
          /lenIV 0 def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.len_iv).to eq(0)
    end

    it "defaults lenIV to 4 if not found" do
      data = "/Private 10 dict def end"
      priv = described_class.new.parse(data)

      expect(priv.len_iv).to eq(4)
    end

    it "returns self for method chaining" do
      data = "/Private 10 dict def end"
      priv = described_class.new

      result = priv.parse(data)

      expect(result).to be(priv)
    end
  end

  describe "#parsed?" do
    it "returns false before parsing" do
      priv = described_class.new

      expect(priv.parsed?).to be false
    end

    it "returns true after parsing" do
      data = "/Private 10 dict def end"
      priv = described_class.new.parse(data)

      expect(priv.parsed?).to be true
    end
  end

  describe "#[]" do
    it "returns nil for unknown key" do
      data = "/Private 10 dict def end"
      priv = described_class.new.parse(data)

      expect(priv[:unknown_key]).to be_nil
    end

    it "returns value for known key" do
      data = <<~DATA
        /Private 10 dict def
          /lenIV 0 def
        end
      DATA

      priv = described_class.new.parse(data)

      expect(priv[:len_iv]).to eq(0)
    end
  end

  describe "#effective_blue_values" do
    it "returns empty array if no BlueValues" do
      priv = described_class.new

      expect(priv.effective_blue_values).to eq([])
    end

    it "scales BlueValues by BlueScale" do
      data = <<~DATA
        /Private 10 dict def
          /BlueValues [-10 0 470 480] def
          /BlueScale 0.05 def
        end
      DATA

      priv = described_class.parse(data)

      expected = [-10, 0, 470, 480].map { |v| v * 0.05 }
      expect(priv.effective_blue_values).to eq(expected)
    end
  end

  describe "#has_blues?" do
    it "returns false when no blues defined" do
      priv = described_class.new

      expect(priv.has_blues?).to be false
    end

    it "returns true when BlueValues defined" do
      data = <<~DATA
        /Private 10 dict def
          /BlueValues [-10 0] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.has_blues?).to be true
    end

    it "returns true when OtherBlues defined" do
      data = <<~DATA
        /Private 10 dict def
          /OtherBlues [-250 -240] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.has_blues?).to be true
    end
  end

  describe "#has_stem_hints?" do
    it "returns false when no stem hints defined" do
      priv = described_class.new

      expect(priv.has_stem_hints?).to be false
    end

    it "returns true when StdHW defined" do
      data = <<~DATA
        /Private 10 dict def
          /StdHW [50] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.has_stem_hints?).to be true
    end

    it "returns true when StdVW defined" do
      data = <<~DATA
        /Private 10 dict def
          /StdVW [60] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.has_stem_hints?).to be true
    end

    it "returns true when StemSnapH defined" do
      data = <<~DATA
        /Private 10 dict def
          /StemSnapH [45 50] def
        end
      DATA

      priv = described_class.parse(data)

      expect(priv.has_stem_hints?).to be true
    end
  end

  describe "#to_type1_format" do
    it "returns Type 1 format with defaults" do
      priv = described_class.new

      result = priv.to_type1_format

      expect(result).to include("/BlueScale 0.039625 def")
      expect(result).to include("/BlueShift 7 def")
      expect(result).to include("/BlueFuzz 1 def")
      expect(result).to include("/lenIV 4 def")
    end

    it "includes BlueValues when set" do
      priv = described_class.new
      priv.blue_values = [-10, 0, 470, 480]

      result = priv.to_type1_format

      expect(result).to include("/BlueValues [-10 0 470 480] def")
    end

    it "includes OtherBlues when set" do
      priv = described_class.new
      priv.other_blues = [-250, -240]

      result = priv.to_type1_format

      expect(result).to include("/OtherBlues [-250 -240] def")
    end

    it "includes StdHW when set" do
      priv = described_class.new
      priv.std_hw = [50.0]

      result = priv.to_type1_format

      expect(result).to include("/StdHW [50.0] def")
    end

    it "includes ForceBold when true" do
      priv = described_class.new
      priv.force_bold = true

      result = priv.to_type1_format

      expect(result).to include("/ForceBold true def")
    end

    it "excludes ForceBold when false" do
      priv = described_class.new
      priv.force_bold = false

      result = priv.to_type1_format

      expect(result).not_to include("/ForceBold")
    end

    it "formats complete dictionary correctly" do
      priv = described_class.new
      priv.blue_values = [-10, 0, 470, 480]
      priv.other_blues = [-250, -240]
      priv.blue_scale = 0.05
      priv.blue_shift = 8
      priv.std_hw = [50.0]

      result = priv.to_type1_format

      expect(result).to include("/BlueValues [-10 0 470 480] def")
      expect(result).to include("/OtherBlues [-250 -240] def")
      expect(result).to include("/BlueScale 0.05 def")
      expect(result).to include("/BlueShift 8 def")
      expect(result).to include("/StdHW [50.0] def")
    end
  end
end
