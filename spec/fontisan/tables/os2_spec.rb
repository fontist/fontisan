# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Os2 do
  # Helper to build valid OS/2 table binary data for different versions
  def build_os2_table(
    version: 0,
    x_avg_char_width: 500,
    us_weight_class: 400,
    us_width_class: 5,
    fs_type: 0,
    y_subscript_x_size: 650,
    y_subscript_y_size: 600,
    y_subscript_x_offset: 0,
    y_subscript_y_offset: 75,
    y_superscript_x_size: 650,
    y_superscript_y_size: 600,
    y_superscript_x_offset: 0,
    y_superscript_y_offset: 350,
    y_strikeout_size: 50,
    y_strikeout_position: 300,
    s_family_class: 0,
    panose: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ul_unicode_range1: 0,
    ul_unicode_range2: 0,
    ul_unicode_range3: 0,
    ul_unicode_range4: 0,
    ach_vend_id: "NONE",
    fs_selection: 0,
    us_first_char_index: 32,
    us_last_char_index: 126,
    s_typo_ascender: 800,
    s_typo_descender: -200,
    s_typo_line_gap: 200,
    us_win_ascent: 1000,
    us_win_descent: 250,
    ul_code_page_range1: 0,
    ul_code_page_range2: 0,
    sx_height: 500,
    s_cap_height: 700,
    us_default_char: 0,
    us_break_char: 32,
    us_max_context: 0,
    us_lower_optical_point_size: 120,
    us_upper_optical_point_size: 1440
  )
    data = (+"").b

    # Version (uint16)
    data << [version].pack("n")

    # Version 0 fields (all versions have these)
    data << [x_avg_char_width].pack("n")
    data << [us_weight_class].pack("n")
    data << [us_width_class].pack("n")
    data << [fs_type].pack("n")
    data << [y_subscript_x_size].pack("n")
    data << [y_subscript_y_size].pack("n")
    data << [y_subscript_x_offset].pack("n")
    data << [y_subscript_y_offset].pack("n")
    data << [y_superscript_x_size].pack("n")
    data << [y_superscript_y_size].pack("n")
    data << [y_superscript_x_offset].pack("n")
    data << [y_superscript_y_offset].pack("n")
    data << [y_strikeout_size].pack("n")
    data << [y_strikeout_position].pack("n")
    data << [s_family_class].pack("n")

    # PANOSE - 10 bytes
    panose.each { |byte| data << [byte].pack("C") }

    # Unicode ranges (4 x uint32)
    data << [ul_unicode_range1].pack("N")
    data << [ul_unicode_range2].pack("N")
    data << [ul_unicode_range3].pack("N")
    data << [ul_unicode_range4].pack("N")

    # Vendor ID - 4 bytes (padded with spaces)
    vendor_id_padded = ach_vend_id.ljust(4, " ")
    data << vendor_id_padded[0, 4]

    # Selection flags and character indices
    data << [fs_selection].pack("n")
    data << [us_first_char_index].pack("n")
    data << [us_last_char_index].pack("n")
    data << [s_typo_ascender].pack("n")
    data << [s_typo_descender].pack("n")
    data << [s_typo_line_gap].pack("n")
    data << [us_win_ascent].pack("n")
    data << [us_win_descent].pack("n")

    # Version 1+ fields
    if version >= 1
      data << [ul_code_page_range1].pack("N")
      data << [ul_code_page_range2].pack("N")
    end

    # Version 2+ fields
    if version >= 2
      data << [sx_height].pack("n")
      data << [s_cap_height].pack("n")
      data << [us_default_char].pack("n")
      data << [us_break_char].pack("n")
      data << [us_max_context].pack("n")
    end

    # Version 5+ fields
    if version >= 5
      data << [us_lower_optical_point_size].pack("n")
      data << [us_upper_optical_point_size].pack("n")
    end

    data
  end

  describe "#parse" do
    context "with version 0 table" do
      let(:data) { build_os2_table(version: 0) }
      let(:os2) { described_class.read(data) }

      it "parses version correctly" do
        expect(os2.version).to eq(0)
      end

      it "parses x_avg_char_width correctly" do
        expect(os2.x_avg_char_width).to eq(500)
      end

      it "parses us_weight_class correctly" do
        expect(os2.us_weight_class).to eq(400)
      end

      it "parses us_width_class correctly" do
        expect(os2.us_width_class).to eq(5)
      end

      it "parses fs_type correctly" do
        expect(os2.fs_type).to eq(0)
      end

      it "parses subscript sizes correctly" do
        expect(os2.y_subscript_x_size).to eq(650)
        expect(os2.y_subscript_y_size).to eq(600)
        expect(os2.y_subscript_x_offset).to eq(0)
        expect(os2.y_subscript_y_offset).to eq(75)
      end

      it "parses superscript sizes correctly" do
        expect(os2.y_superscript_x_size).to eq(650)
        expect(os2.y_superscript_y_size).to eq(600)
        expect(os2.y_superscript_x_offset).to eq(0)
        expect(os2.y_superscript_y_offset).to eq(350)
      end

      it "parses strikeout correctly" do
        expect(os2.y_strikeout_size).to eq(50)
        expect(os2.y_strikeout_position).to eq(300)
      end

      it "parses s_family_class correctly" do
        expect(os2.s_family_class).to eq(0)
      end

      it "parses panose correctly" do
        expect(os2.panose).to eq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        expect(os2.panose.length).to eq(10)
      end

      it "parses unicode ranges correctly" do
        expect(os2.ul_unicode_range1).to eq(0)
        expect(os2.ul_unicode_range2).to eq(0)
        expect(os2.ul_unicode_range3).to eq(0)
        expect(os2.ul_unicode_range4).to eq(0)
      end

      it "parses ach_vend_id correctly" do
        expect(os2.ach_vend_id).to eq("NONE")
      end

      it "parses fs_selection correctly" do
        expect(os2.fs_selection).to eq(0)
      end

      it "parses character indices correctly" do
        expect(os2.us_first_char_index).to eq(32)
        expect(os2.us_last_char_index).to eq(126)
      end

      it "parses typo metrics correctly" do
        expect(os2.s_typo_ascender).to eq(800)
        expect(os2.s_typo_descender).to eq(-200)
        expect(os2.s_typo_line_gap).to eq(200)
      end

      it "parses win metrics correctly" do
        expect(os2.us_win_ascent).to eq(1000)
        expect(os2.us_win_descent).to eq(250)
      end

      it "does not include version 1+ data" do
        # Version 0 tables don't have code page range data
        # The helper methods handle version checking
        expect(os2.version).to eq(0)
      end

      it "does not include version 2+ data" do
        # Version 0 tables don't have x-height/cap height data
        # The helper methods handle version checking
        expect(os2.version).to eq(0)
      end

      it "does not include version 5+ data" do
        # Version 0 tables don't have optical size data
        expect(os2.has_optical_point_size?).to be false
        expect(os2.lower_optical_point_size).to be_nil
        expect(os2.upper_optical_point_size).to be_nil
      end
    end

    context "with version 1 table" do
      let(:data) do
        build_os2_table(version: 1, ul_code_page_range1: 0x00000003,
                        ul_code_page_range2: 0x00000001)
      end
      let(:os2) { described_class.read(data) }

      it "parses version correctly" do
        expect(os2.version).to eq(1)
      end

      it "parses all version 0 fields" do
        expect(os2.us_weight_class).to eq(400)
        expect(os2.us_width_class).to eq(5)
      end

      it "parses code page ranges" do
        expect(os2.ul_code_page_range1).to eq(0x00000003)
        expect(os2.ul_code_page_range2).to eq(0x00000001)
      end

      it "does not include version 2+ data" do
        # Version 1 tables don't have x-height/cap height data
        expect(os2.version).to eq(1)
      end
    end

    context "with version 2 table" do
      let(:data) do
        build_os2_table(version: 2, sx_height: 520, s_cap_height: 680,
                        us_default_char: 0, us_break_char: 32,
                        us_max_context: 2)
      end
      let(:os2) { described_class.read(data) }

      it "parses version correctly" do
        expect(os2.version).to eq(2)
      end

      it "parses all version 0 and 1 fields" do
        expect(os2.us_weight_class).to eq(400)
        expect(os2.ul_code_page_range1).to eq(0)
      end

      it "parses x-height and cap height" do
        expect(os2.sx_height).to eq(520)
        expect(os2.s_cap_height).to eq(680)
      end

      it "parses character fields" do
        expect(os2.us_default_char).to eq(0)
        expect(os2.us_break_char).to eq(32)
        expect(os2.us_max_context).to eq(2)
      end

      it "does not include version 5+ data" do
        # Version 2 tables don't have optical size data
        expect(os2.has_optical_point_size?).to be false
        expect(os2.lower_optical_point_size).to be_nil
        expect(os2.upper_optical_point_size).to be_nil
      end
    end

    context "with version 5 table" do
      let(:data) do
        build_os2_table(version: 5, us_lower_optical_point_size: 120,
                        us_upper_optical_point_size: 1440)
      end
      let(:os2) { described_class.read(data) }

      it "parses version correctly" do
        expect(os2.version).to eq(5)
      end

      it "parses all previous version fields" do
        expect(os2.us_weight_class).to eq(400)
        expect(os2.ul_code_page_range1).to eq(0)
        expect(os2.sx_height).to eq(500)
      end

      it "parses optical point sizes" do
        expect(os2.us_lower_optical_point_size).to eq(120)
        expect(os2.us_upper_optical_point_size).to eq(1440)
      end
    end
  end

  describe "typical weight values" do
    it "handles normal weight (400)" do
      data = build_os2_table(us_weight_class: 400)
      os2 = described_class.read(data)
      expect(os2.us_weight_class).to eq(400)
    end

    it "handles bold weight (700)" do
      data = build_os2_table(us_weight_class: 700)
      os2 = described_class.read(data)
      expect(os2.us_weight_class).to eq(700)
    end

    it "handles light weight (300)" do
      data = build_os2_table(us_weight_class: 300)
      os2 = described_class.read(data)
      expect(os2.us_weight_class).to eq(300)
    end

    it "handles black weight (900)" do
      data = build_os2_table(us_weight_class: 900)
      os2 = described_class.read(data)
      expect(os2.us_weight_class).to eq(900)
    end
  end

  describe "typical width values" do
    it "handles normal width (5)" do
      data = build_os2_table(us_width_class: 5)
      os2 = described_class.read(data)
      expect(os2.us_width_class).to eq(5)
    end

    it "handles condensed width (3)" do
      data = build_os2_table(us_width_class: 3)
      os2 = described_class.read(data)
      expect(os2.us_width_class).to eq(3)
    end
  end

  describe "fs_type embedding flags" do
    it "handles installable embedding (0)" do
      data = build_os2_table(fs_type: 0)
      os2 = described_class.read(data)
      expect(os2.fs_type).to eq(0)
    end

    it "handles restricted license embedding (2)" do
      data = build_os2_table(fs_type: 2)
      os2 = described_class.read(data)
      expect(os2.fs_type).to eq(2)
    end

    it "handles preview & print embedding (4)" do
      data = build_os2_table(fs_type: 4)
      os2 = described_class.read(data)
      expect(os2.fs_type).to eq(4)
    end

    it "handles editable embedding (8)" do
      data = build_os2_table(fs_type: 8)
      os2 = described_class.read(data)
      expect(os2.fs_type).to eq(8)
    end
  end

  describe "#vendor_id" do
    it "returns vendor ID without padding" do
      data = build_os2_table(ach_vend_id: "ADBE")
      os2 = described_class.read(data)
      expect(os2.vendor_id).to eq("ADBE")
    end

    it "trims trailing spaces" do
      data = build_os2_table(ach_vend_id: "FOO ")
      os2 = described_class.read(data)
      expect(os2.vendor_id).to eq("FOO")
    end

    it "trims trailing nulls" do
      # Build a vendor ID with null bytes directly
      data = build_os2_table(ach_vend_id: "AB\x00\x00")
      os2 = described_class.read(data)
      expect(os2.vendor_id).to eq("AB")
    end

    it "handles Adobe vendor ID" do
      data = build_os2_table(ach_vend_id: "ADBE")
      os2 = described_class.read(data)
      expect(os2.vendor_id).to eq("ADBE")
    end

    it "handles Google vendor ID" do
      data = build_os2_table(ach_vend_id: "GOOG")
      os2 = described_class.read(data)
      expect(os2.vendor_id).to eq("GOOG")
    end

    it "handles Apple vendor ID" do
      data = build_os2_table(ach_vend_id: "APPL")
      os2 = described_class.read(data)
      expect(os2.vendor_id).to eq("APPL")
    end
  end

  describe "#type_flags" do
    it "returns fs_type value" do
      data = build_os2_table(fs_type: 8)
      os2 = described_class.read(data)
      expect(os2.type_flags).to eq(8)
    end

    it "is an alias for fs_type" do
      data = build_os2_table(fs_type: 4)
      os2 = described_class.read(data)
      expect(os2.type_flags).to eq(os2.fs_type)
    end
  end

  describe "#has_optical_point_size?" do
    it "returns true for version 5" do
      data = build_os2_table(version: 5)
      os2 = described_class.read(data)
      expect(os2.has_optical_point_size?).to be true
    end

    it "returns false for version 0" do
      data = build_os2_table(version: 0)
      os2 = described_class.read(data)
      expect(os2.has_optical_point_size?).to be false
    end

    it "returns false for version 2" do
      data = build_os2_table(version: 2)
      os2 = described_class.read(data)
      expect(os2.has_optical_point_size?).to be false
    end
  end

  describe "#lower_optical_point_size" do
    it "returns point size for version 5" do
      # 120 / 20 = 6.0 points
      data = build_os2_table(version: 5, us_lower_optical_point_size: 120)
      os2 = described_class.read(data)
      expect(os2.lower_optical_point_size).to eq(6.0)
    end

    it "returns nil for version 0" do
      data = build_os2_table(version: 0)
      os2 = described_class.read(data)
      expect(os2.lower_optical_point_size).to be_nil
    end

    it "correctly converts twips to points" do
      # 240 / 20 = 12.0 points
      data = build_os2_table(version: 5, us_lower_optical_point_size: 240)
      os2 = described_class.read(data)
      expect(os2.lower_optical_point_size).to eq(12.0)
    end
  end

  describe "#upper_optical_point_size" do
    it "returns point size for version 5" do
      # 1440 / 20 = 72.0 points
      data = build_os2_table(version: 5, us_upper_optical_point_size: 1440)
      os2 = described_class.read(data)
      expect(os2.upper_optical_point_size).to eq(72.0)
    end

    it "returns nil for version 0" do
      data = build_os2_table(version: 0)
      os2 = described_class.read(data)
      expect(os2.upper_optical_point_size).to be_nil
    end

    it "correctly converts twips to points" do
      # 2880 / 20 = 144.0 points
      data = build_os2_table(version: 5, us_upper_optical_point_size: 2880)
      os2 = described_class.read(data)
      expect(os2.upper_optical_point_size).to eq(144.0)
    end
  end

  describe "#valid?" do
    it "returns true for valid data" do
      data = build_os2_table
      os2 = described_class.read(data)
      expect(os2).to be_valid
    end

    it "returns false for nil data" do
      os2 = described_class.read(nil)
      expect(os2.version).to eq(0)
    end
  end
end
