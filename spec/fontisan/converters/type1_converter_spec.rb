# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Fontisan::Converters::Type1Converter do
  let(:converter) { described_class.new }

  describe "#extract_conversion_options" do
    it "extracts ConversionOptions from options hash" do
      conv_options = Fontisan::ConversionOptions.new(from: :type1, to: :otf)
      options = { options: conv_options }

      result = converter.send(:extract_conversion_options, options)

      expect(result).to eq(conv_options)
    end

    it "returns nil when no ConversionOptions provided" do
      options = { target_format: :otf }

      result = converter.send(:extract_conversion_options, options)

      expect(result).to be_nil
    end

    it "returns ConversionOptions when passed directly" do
      conv_options = Fontisan::ConversionOptions.new(from: :type1, to: :otf)

      result = converter.send(:extract_conversion_options, conv_options)

      expect(result).to eq(conv_options)
    end
  end

  describe "#apply_opening_options" do
    let(:mock_charstrings) { instance_double(Fontisan::Type1::CharStrings) }
    let(:mock_font_dictionary) { instance_double(Object) }
    let(:mock_font) do
      instance_double(Fontisan::Type1Font,
                      charstrings: mock_charstrings,
                      font_dictionary: mock_font_dictionary)
    end

    before do
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      # Stub the methods to call the original (no-op) implementation
      allow(converter).to receive_messages(generate_unicode_mappings: nil,
                                           decompose_seac_glyphs: nil)
    end

    it "applies generate_unicode option when set" do
      conv_options = Fontisan::ConversionOptions.new(
        from: :type1,
        to: :otf,
        opening: { generate_unicode: true },
      )

      expect(converter).to receive(:generate_unicode_mappings).with(mock_font)

      converter.send(:apply_opening_options, mock_font, conv_options)
    end

    it "applies decompose_composites option when set" do
      conv_options = Fontisan::ConversionOptions.new(
        from: :type1,
        to: :otf,
        opening: { decompose_composites: true },
      )

      expect(converter).to receive(:decompose_seac_glyphs).with(mock_font)

      converter.send(:apply_opening_options, mock_font, conv_options)
    end

    it "skips opening options when not set" do
      conv_options = Fontisan::ConversionOptions.new(
        from: :type1,
        to: :otf,
        opening: {},
      )

      # Just verify it runs without error
      expect do
        converter.send(:apply_opening_options, mock_font, conv_options)
      end.not_to raise_error
    end

    it "skips opening options when conv_options is nil" do
      # Just verify it runs without error
      expect do
        converter.send(:apply_opening_options, mock_font, nil)
      end.not_to raise_error
    end
  end

  describe "#convert with ConversionOptions" do
    let(:mock_font) do
      # Use a stub that responds to is_a? properly
      font = double("Type1Font")
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      allow(font).to receive(:is_a?).with(Fontisan::OpenTypeFont).and_return(false)
      allow(font).to receive(:is_a?).with(Fontisan::TrueTypeFont).and_return(false)
      allow(font).to receive(:is_a?).with(Fontisan::WoffFont).and_return(false)
      allow(font).to receive(:is_a?).with(Fontisan::Woff2Font).and_return(false)
      allow(font).to receive(:class).and_return(Fontisan::Type1Font)
      font
    end

    before do
      # Stub detect_format to return :type1 (called before validate)
      # Stub validate to prevent errors
      # Stub apply_opening_options to prevent actual option processing
      # Stub conversion methods
      allow(converter).to receive_messages(detect_format: :type1,
                                           validate: nil, apply_opening_options: nil, convert_type1_to_otf: {}, convert_type1_to_ttf: {})
    end

    context "target format detection" do
      it "extracts ConversionOptions from options hash" do
        conv_options = Fontisan::ConversionOptions.new(from: :type1, to: :otf)
        options = { options: conv_options }

        expect do
          converter.convert(mock_font, options)
        end.not_to raise_error
      end

      it "uses ConversionOptions target format when not specified in options" do
        conv_options = Fontisan::ConversionOptions.new(from: :type1, to: :ttf)
        options = { options: conv_options }

        # When target is TTF, convert_type1_to_ttf is called with the ConversionOptions
        expect(converter).to receive(:convert_type1_to_ttf).with(mock_font,
                                                                 conv_options)

        converter.convert(mock_font, options)
      end
    end

    context "with recommended options" do
      it "uses recommended options for Type 1 to OTF" do
        options = Fontisan::ConversionOptions.recommended(from: :type1,
                                                          to: :otf)

        expect do
          converter.convert(mock_font, options: options)
        end.not_to raise_error
      end
    end

    context "with preset options" do
      it "uses type1_to_modern preset" do
        options = Fontisan::ConversionOptions.from_preset(:type1_to_modern)

        expect do
          converter.convert(mock_font, options: options)
        end.not_to raise_error
      end
    end

    context "with Hash options (backward compatibility)" do
      it "accepts Hash options without ConversionOptions" do
        expect do
          converter.convert(mock_font, target_format: :otf)
        end.not_to raise_error
      end
    end
  end

  describe "#build_private_dict_hash" do
    let(:mock_private_dict) do
      dict = double("Tables::Cff::PrivateDict")
      allow(dict).to receive_messages(nominal_width: 0, default_width: 500,
                                      blue_values: [-10, 0, 470, 480], other_blues: [-250, -240], family_blues: [], family_other_blues: [], blue_scale: 0.039625, blue_shift: 7, blue_fuzz: 1, std_hw: [50], std_vw: [60], stem_snap_h: [], stem_snap_v: [], force_bold: false, language_group: 0, expansion_factor: 0.06, initial_random_seed: 0)
      dict
    end

    it "builds hash from CFF Private dict" do
      result = converter.send(:build_private_dict_hash, mock_private_dict)

      expect(result[:nominal_width]).to eq(0)
      expect(result[:default_width]).to eq(500)
      expect(result[:blue_values]).to eq([-10, 0, 470, 480])
      expect(result[:other_blues]).to eq([-250, -240])
      expect(result[:blue_scale]).to eq(0.039625)
      expect(result[:blue_shift]).to eq(7)
      expect(result[:blue_fuzz]).to eq(1)
      expect(result[:std_hw]).to eq([50])
      expect(result[:std_vw]).to eq([60])
      expect(result[:force_bold]).to be false
      expect(result[:language_group]).to eq(0)
    end

    it "handles nil private dict" do
      result = converter.send(:build_private_dict_hash, nil)

      expect(result).to eq({})
    end

    it "uses defaults for missing values" do
      dict = double("Tables::Cff::PrivateDict")
      allow(dict).to receive_messages(nominal_width: nil, default_width: nil,
                                      blue_values: nil, other_blues: nil, family_blues: nil, family_other_blues: nil, blue_scale: nil, blue_shift: nil, blue_fuzz: nil, std_hw: nil, std_vw: nil, stem_snap_h: nil, stem_snap_v: nil, force_bold: nil, language_group: nil, expansion_factor: nil, initial_random_seed: nil)

      result = converter.send(:build_private_dict_hash, dict)

      expect(result[:nominal_width]).to be_nil
      expect(result[:default_width]).to be_nil
      expect(result[:blue_values]).to eq([])
      expect(result[:blue_scale]).to eq(0.039625)
    end
  end

  describe "CFF to Type 1 conversion" do
    let(:mock_cff_table) do
      cff = double("Tables::Cff")
      allow(cff).to receive(:charstrings_index).with(0).and_return(mock_charstrings_index)
      allow(cff).to receive(:private_dict).with(0).and_return(mock_private_dict)
      cff
    end

    let(:mock_charstrings_index) do
      charstrings = double("Tables::Cff::CharstringsIndex")
      allow(charstrings).to receive(:count).and_return(2)
      allow(charstrings).to receive(:[]).with(0).and_return([226, 50, 21].pack("C*")) # rmoveto 100 50
      allow(charstrings).to receive(:[]).with(1).and_return([189, 6].pack("C*")) # hlineto 50
      charstrings
    end

    let(:mock_private_dict) do
      dict = double("Tables::Cff::PrivateDict")
      allow(dict).to receive_messages(nominal_width: 0, default_width: 500,
                                      blue_values: [], other_blues: [], family_blues: [], family_other_blues: [], blue_scale: 0.039625, blue_shift: 7, blue_fuzz: 1, std_hw: [], std_vw: [], stem_snap_h: [], stem_snap_v: [], force_bold: false, language_group: 0, expansion_factor: 0.06, initial_random_seed: 0)
      dict
    end

    let(:mock_open_type_font) do
      font = double("OpenTypeFont")
      allow(font).to receive(:table).with("CFF ").and_return(mock_cff_table)
      allow(font).to receive(:glyph_name).with(0).and_return("glyph1")
      allow(font).to receive(:glyph_name).with(1).and_return("glyph2")
      font
    end

    it "converts CFF CharStrings to Type 1 format" do
      result = converter.send(:convert_otf_to_type1, mock_open_type_font)

      expect(result).to be_a(Hash)
      expect(result.key?(:pfb)).to be true
    end

    it "raises error when CFF table not found" do
      font = double("OpenTypeFont")
      allow(font).to receive(:table).with("CFF ").and_return(nil)

      expect do
        converter.send(:convert_otf_to_type1, font)
      end.to raise_error(Fontisan::Error, "CFF table not found")
    end

    it "raises error when CharStrings INDEX not found" do
      font = double("OpenTypeFont")
      cff = double("Tables::Cff")
      allow(font).to receive(:table).with("CFF ").and_return(cff)
      allow(cff).to receive(:charstrings_index).with(0).and_return(nil)

      expect do
        converter.send(:convert_otf_to_type1, font)
      end.to raise_error(Fontisan::Error, "CharStrings INDEX not found")
    end
  end

  describe "#build_head_table" do
    let(:mock_font_dict) do
      dict = double("font_dictionary")
      allow(dict).to receive(:font_bbox).and_return([50, -100, 900, 800])
      dict
    end

    let(:mock_type1_font) do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: mock_font_dict,
                                      version: "001.000")
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      font
    end

    it "builds head table with correct structure" do
      result = converter.send(:build_head_table, mock_type1_font)

      expect(result).to be_a(String)
      expect(result.bytesize).to be >= 54 # Minimum head table size
    end

    it "includes correct magic number" do
      result = converter.send(:build_head_table, mock_type1_font)

      # Magic number is at offset 12 (bytes 12-15)
      magic = result[12..15].unpack1("N")
      expect(magic).to eq(0x5F0F3CF5)
    end

    it "sets units per em to 1000 (Type 1 standard)" do
      result = converter.send(:build_head_table, mock_type1_font)

      # Units per em is at offset 18 (bytes 18-19)
      upem = result[18..19].unpack1("n")
      expect(upem).to eq(1000)
    end

    it "includes font bounding box" do
      result = converter.send(:build_head_table, mock_type1_font)

      # Bounding box is at offset 36-43 (4 x int16)
      x_min = result[36..37].unpack1("s>")
      y_min = result[38..39].unpack1("s>")
      x_max = result[40..41].unpack1("s>")
      y_max = result[42..43].unpack1("s>")

      expect(x_min).to eq(50)
      expect(y_min).to eq(-100)
      expect(x_max).to eq(900)
      expect(y_max).to eq(800)
    end

    it "handles missing font dictionary" do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: nil, version: "001.000")
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_head_table, font)

      # Should use default bbox [0, 0, 1000, 1000]
      x_min = result[36..37].unpack1("s>")
      y_min = result[38..39].unpack1("s>")
      x_max = result[40..41].unpack1("s>")
      y_max = result[42..43].unpack1("s>")

      expect(x_min).to eq(0)
      expect(y_min).to eq(0)
      expect(x_max).to eq(1000)
      expect(y_max).to eq(1000)
    end

    it "parses version string correctly" do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: mock_font_dict,
                                      version: "002.500")
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_head_table, font)

      # Version is at offset 0-3 (Fixed 16.16)
      # 002.500 => 2.5 => 0x00028000
      version = result[0..3].unpack1("N")
      expect(version).to eq(0x00028000)
    end
  end

  describe "#build_hhea_table" do
    let(:mock_private_dict) do
      dict = double("private_dict")
      allow(dict).to receive(:blue_values).and_return([-20, 0, 750, 770])
      dict
    end

    let(:mock_font_dict) do
      dict = double("font_dictionary")
      allow(dict).to receive(:font_bbox).and_return([50, -200, 950, 800])
      dict
    end

    let(:mock_charstrings) do
      cs = double("charstrings")
      allow(cs).to receive(:count).and_return(250)
      cs
    end

    let(:mock_type1_font) do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: mock_font_dict,
                                      private_dict: mock_private_dict, charstrings: mock_charstrings)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      font
    end

    it "builds hhea table with correct structure" do
      result = converter.send(:build_hhea_table, mock_type1_font)

      expect(result).to be_a(String)
      expect(result.bytesize).to be >= 36 # hhea table size
    end

    it "uses BlueValues for ascent when available" do
      result = converter.send(:build_hhea_table, mock_type1_font)

      # Ascent is at offset 4-5 (int16)
      ascent = result[4..5].unpack1("s>")
      expect(ascent).to eq(770) # BlueValues[3]
    end

    it "uses BlueValues for descent when available" do
      result = converter.send(:build_hhea_table, mock_type1_font)

      # Descent is at offset 6-7 (int16)
      descent = result[6..7].unpack1("s>")
      expect(descent).to eq(-20)  # BlueValues[0]
    end

    it "falls back to font bbox when no BlueValues" do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: mock_font_dict,
                                      private_dict: nil, charstrings: mock_charstrings)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_hhea_table, font)

      ascent = result[4..5].unpack1("s>")
      descent = result[6..7].unpack1("s>")

      expect(ascent).to eq(800)   # font_bbox[3]
      expect(descent).to eq(-200) # font_bbox[1]
    end

    it "sets number of HMetrics correctly" do
      result = converter.send(:build_hhea_table, mock_type1_font)

      # Number of HMetrics is at offset 34-35 (uint16)
      num_hmetrics = result[34..35].unpack1("n")
      expect(num_hmetrics).to eq(250)
    end

    it "ensures minimum glyph count of 1" do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: mock_font_dict,
                                      private_dict: mock_private_dict, charstrings: nil)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_hhea_table, font)

      num_hmetrics = result[34..35].unpack1("n")
      expect(num_hmetrics).to be >= 1
    end
  end

  describe "#build_maxp_table" do
    let(:mock_charstrings) do
      cs = double("charstrings")
      allow(cs).to receive(:count).and_return(150)
      cs
    end

    let(:mock_type1_font) do
      font = double("Type1Font")
      allow(font).to receive(:charstrings).and_return(mock_charstrings)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      font
    end

    it "builds maxp table with version 0.5 for CFF fonts" do
      result = converter.send(:build_maxp_table, mock_type1_font)

      # Version is at offset 0-3 (Fixed 16.16)
      version = result[0..3].unpack1("N")
      expect(version).to eq(0x00005000) # Version 0.5
    end

    it "sets number of glyphs correctly" do
      result = converter.send(:build_maxp_table, mock_type1_font)

      # Num glyphs is at offset 4-5 (uint16)
      num_glyphs = result[4..5].unpack1("n")
      expect(num_glyphs).to eq(150)
    end

    it "ensures minimum glyph count of 1" do
      font = double("Type1Font")
      allow(font).to receive(:charstrings).and_return(nil)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_maxp_table, font)

      num_glyphs = result[4..5].unpack1("n")
      expect(num_glyphs).to be >= 1
    end

    it "has minimum table size of 6 bytes" do
      result = converter.send(:build_maxp_table, mock_type1_font)

      expect(result.bytesize).to eq(6) # Version (4) + num_glyphs (2)
    end
  end

  describe "#build_name_table" do
    let(:mock_font_info) do
      info = double("font_info")
      allow(info).to receive_messages(family_name: "TestFamily",
                                      full_name: "TestFont Regular", weight: "Regular", version: "001.000", copyright: "Copyright 2024", notice: "Test Font")
      info
    end

    let(:mock_font_dict) do
      dict = double("font_dictionary")
      allow(dict).to receive(:font_info).and_return(mock_font_info)
      dict
    end

    let(:mock_type1_font) do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: mock_font_dict,
                                      font_name: "TestFont", version: "001.000")
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      font
    end

    it "builds name table with correct structure" do
      result = converter.send(:build_name_table, mock_type1_font)

      expect(result).to be_a(String)
      expect(result.bytesize).to be >= 6 # Minimum header size
    end

    it "sets format selector to 0" do
      result = converter.send(:build_name_table, mock_type1_font)

      format = result[0..1].unpack1("n")
      expect(format).to eq(0)
    end

    it "includes name records count" do
      result = converter.send(:build_name_table, mock_type1_font)

      count = result[2..3].unpack1("n")
      expect(count).to be > 0
    end

    it "includes string storage offset" do
      result = converter.send(:build_name_table, mock_type1_font)

      offset = result[4..5].unpack1("n")
      expect(offset).to be >= 6
    end

    it "uses Windows platform ID (3)" do
      result = converter.send(:build_name_table, mock_type1_font)

      # First name record starts at offset 6
      platform_id = result[6..7].unpack1("n")
      expect(platform_id).to eq(3)  # Windows
    end

    it "uses Unicode BMP encoding ID (1)" do
      result = converter.send(:build_name_table, mock_type1_font)

      encoding_id = result[8..9].unpack1("n")
      expect(encoding_id).to eq(1)  # Unicode BMP
    end

    it "uses US English language ID (0x0409)" do
      result = converter.send(:build_name_table, mock_type1_font)

      language_id = result[10..11].unpack1("n")
      expect(language_id).to eq(0x0409)
    end

    it "filters out empty name records" do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: nil,
                                      font_name: "TestFont", version: "001.000")
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_name_table, font)

      count = result[2..3].unpack1("n")
      # Should have at least the font name record (name_id 6)
      expect(count).to be >= 1
    end
  end

  describe "#build_os2_table" do
    let(:mock_font_info) do
      info = double("font_info")
      allow(info).to receive(:weight).and_return("Bold")
      info
    end

    let(:mock_font_dict) do
      dict = double("font_dictionary")
      allow(dict).to receive_messages(font_bbox: [50, -250, 900, 750],
                                      font_info: mock_font_info)
      dict
    end

    let(:mock_private_dict) do
      dict = double("private_dict")
      allow(dict).to receive(:blue_values).and_return([-250, -240, 700, 720])
      dict
    end

    let(:mock_type1_font) do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: mock_font_dict,
                                      private_dict: mock_private_dict)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      font
    end

    it "builds OS/2 table with version 4" do
      result = converter.send(:build_os2_table, mock_type1_font)

      # Version is at offset 0-1 (uint16)
      version = result[0..1].unpack1("n")
      expect(version).to eq(4)
    end

    it "sets weight class correctly" do
      result = converter.send(:build_os2_table, mock_type1_font)

      # Weight class is at offset 4-5 (uint16)
      weight_class = result[4..5].unpack1("n")
      expect(weight_class).to eq(700) # Bold
    end

    it "maps weight names to correct classes" do
      weights = {
        "Thin" => 100,
        "ExtraLight" => 200,
        "Light" => 300,
        "Regular" => 400,
        "Medium" => 400,
        "SemiBold" => 600,
        "Bold" => 700,
        "ExtraBold" => 800,
        "Black" => 900,
      }

      weights.each do |weight_name, expected_class|
        info = double("font_info")
        allow(info).to receive(:weight).and_return(weight_name)

        dict = double("font_dictionary")
        allow(dict).to receive_messages(font_bbox: [0, 0, 1000, 1000],
                                        font_info: info)

        font = double("Type1Font")
        allow(font).to receive_messages(font_dictionary: dict,
                                        private_dict: nil)
        allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

        result = converter.send(:build_os2_table, font)
        weight_class = result[4..5].unpack1("n")

        expect(weight_class).to eq(expected_class)
      end
    end

    it "includes PANOSE data" do
      result = converter.send(:build_os2_table, mock_type1_font)

      # PANOSE is at offset 32-41 (10 bytes)
      panose = result[32..41].unpack("C*")
      expect(panose.length).to eq(10)
      expect(panose[0]).to eq(2) # Latin Text
    end

    it "includes vendor ID" do
      result = converter.send(:build_os2_table, mock_type1_font)

      # Vendor ID is at offset 58-61 (4 bytes)
      vendor_id = result[58..61]
      expect(vendor_id).to eq("UKWN") # Unknown
    end

    it "sets fsSelection for regular weight" do
      info = double("font_info")
      allow(info).to receive(:weight).and_return("Regular")

      dict = double("font_dictionary")
      allow(dict).to receive_messages(font_bbox: [0, 0, 1000, 1000],
                                      font_info: info)

      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: dict, private_dict: nil)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_os2_table, font)

      # fsSelection is at offset 62-63 (uint16)
      fs_selection = result[62..63].unpack1("n")
      expect(fs_selection & 0x40).to eq(0x40)  # REGULAR bit
    end

    it "sets fsSelection for bold weight" do
      result = converter.send(:build_os2_table, mock_type1_font)

      fs_selection = result[62..63].unpack1("n")
      expect(fs_selection & 0x20).to eq(0x20)  # BOLD bit
    end
  end

  describe "#build_post_table" do
    let(:mock_font_info) do
      info = double("font_info")
      allow(info).to receive_messages(italic_angle: 0,
                                      underline_position: -100, underline_thickness: 50, is_fixed_pitch: false)
      info
    end

    let(:mock_font_dict) do
      dict = double("font_dictionary")
      allow(dict).to receive(:font_info).and_return(mock_font_info)
      dict
    end

    let(:mock_type1_font) do
      font = double("Type1Font")
      allow(font).to receive(:font_dictionary).and_return(mock_font_dict)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      font
    end

    it "builds post table with version 3.0 for CFF fonts" do
      result = converter.send(:build_post_table, mock_type1_font)

      # Version is at offset 0-3 (Fixed 16.16)
      version = result[0..3].unpack1("N")
      expect(version).to eq(0x00030000) # Version 3.0
    end

    it "sets italic angle correctly" do
      result = converter.send(:build_post_table, mock_type1_font)

      # Italic angle is at offset 4-7 (Fixed 16.16)
      italic_angle = result[4..7].unpack1("N")
      expect(italic_angle).to eq(0) # 0 degrees
    end

    it "sets underline position" do
      result = converter.send(:build_post_table, mock_type1_font)

      # Underline position is at offset 8-9 (int16)
      underline_position = result[8..9].unpack1("s>")
      expect(underline_position).to eq(-100)
    end

    it "sets underline thickness" do
      result = converter.send(:build_post_table, mock_type1_font)

      # Underline thickness is at offset 10-11 (int16)
      underline_thickness = result[10..11].unpack1("s>")
      expect(underline_thickness).to eq(50)
    end

    it "sets fixed pitch flag correctly" do
      result = converter.send(:build_post_table, mock_type1_font)

      # Fixed pitch is at offset 12-15 (uint32)
      is_fixed_pitch = result[12..15].unpack1("N")
      expect(is_fixed_pitch).to eq(0)  # Not monospace
    end

    it "handles monospace font" do
      info = double("font_info")
      allow(info).to receive_messages(italic_angle: 0,
                                      underline_position: -100, underline_thickness: 50, is_fixed_pitch: true)

      dict = double("font_dictionary")
      allow(dict).to receive(:font_info).and_return(info)

      font = double("Type1Font")
      allow(font).to receive(:font_dictionary).and_return(dict)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_post_table, font)

      is_fixed_pitch = result[12..15].unpack1("N")
      expect(is_fixed_pitch).to eq(1)  # Monospace
    end

    it "has minimum table size of 32 bytes" do
      result = converter.send(:build_post_table, mock_type1_font)

      expect(result.bytesize).to eq(32) # Version 3.0 post table size
    end
  end

  describe "#build_cmap_table" do
    let(:mock_charstrings) do
      cs = double("charstrings")
      allow(cs).to receive_messages(encoding: {
                                      ".notdef" => 0,
                                      "A" => 1,
                                      "B" => 2,
                                      "C" => 3,
                                    }, glyph_names: [".notdef", "A", "B", "C"])
      cs
    end

    let(:mock_type1_font) do
      font = double("Type1Font")
      allow(font).to receive(:charstrings).and_return(mock_charstrings)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      font
    end

    it "builds cmap table with correct structure" do
      result = converter.send(:build_cmap_table, mock_type1_font)

      expect(result).to be_a(String)
      expect(result.bytesize).to be >= 4 # Minimum header size
    end

    it "sets cmap version to 0" do
      result = converter.send(:build_cmap_table, mock_type1_font)

      version = result[0..1].unpack1("n")
      expect(version).to eq(0)
    end

    it "includes one encoding record" do
      result = converter.send(:build_cmap_table, mock_type1_font)

      num_tables = result[2..3].unpack1("n")
      expect(num_tables).to eq(1)
    end

    it "uses Windows platform ID (3)" do
      result = converter.send(:build_cmap_table, mock_type1_font)

      platform_id = result[4..5].unpack1("n")
      expect(platform_id).to eq(3)  # Windows
    end

    it "uses Unicode BMP encoding ID (1)" do
      result = converter.send(:build_cmap_table, mock_type1_font)

      encoding_id = result[6..7].unpack1("n")
      expect(encoding_id).to eq(1)  # Unicode BMP
    end

    it "includes format 4 subtable" do
      result = converter.send(:build_cmap_table, mock_type1_font)

      subtable_offset = result[8..11].unpack1("N")
      format = result[subtable_offset..subtable_offset + 1].unpack1("n")
      expect(format).to eq(4) # Format 4
    end

    it "handles empty encoding" do
      cs = double("charstrings")
      allow(cs).to receive_messages(encoding: {}, glyph_names: [])

      font = double("Type1Font")
      allow(font).to receive(:charstrings).and_return(cs)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_cmap_table, font)

      # Should still produce valid cmap table
      expect(result.bytesize).to be >= 12
    end
  end

  describe "#build_cff_font_dict" do
    let(:mock_font_info) do
      info = double("font_info")
      allow(info).to receive_messages(version: "001.000",
                                      notice: "Copyright notice", copyright: "Copyright 2024", full_name: "TestFont", family_name: "TestFamily", weight: "Regular")
      info
    end

    let(:mock_font_dict) do
      dict = double("font_dictionary")
      allow(dict).to receive_messages(version: "001.000", notice: "Copyright notice", copyright: "Copyright 2024", full_name: "TestFont", family_name: "TestFamily", weight: "Regular", font_bbox: [0, -100, 1000, 900], font_matrix: [0.001, 0, 0, 0.001, 0,
                                                                                                                                                                                                                                       0], font_info: mock_font_info)
      dict
    end

    let(:mock_charstrings) do
      cs = double("charstrings")
      allow(cs).to receive(:encoding).and_return({ "A" => 1 })
      cs
    end

    let(:mock_type1_font) do
      font = double("Type1Font")
      allow(font).to receive_messages(font_dictionary: mock_font_dict,
                                      font_name: "TestFont", charstrings: mock_charstrings)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      font
    end

    it "builds CFF font dictionary hash" do
      result = converter.send(:build_cff_font_dict, mock_type1_font)

      expect(result).to be_a(Hash)
      expect(result[:version]).to eq("001.000")
      expect(result[:full_name]).to eq("TestFont")
      expect(result[:family_name]).to eq("TestFamily")
    end

    it "includes font bounding box" do
      result = converter.send(:build_cff_font_dict, mock_type1_font)

      expect(result[:font_b_box]).to eq([0, -100, 1000, 900])
    end

    it "includes font matrix" do
      result = converter.send(:build_cff_font_dict, mock_type1_font)

      expect(result[:font_matrix]).to eq([0.001, 0, 0, 0.001, 0, 0])
    end

    it "includes charset from charstrings encoding" do
      result = converter.send(:build_cff_font_dict, mock_type1_font)

      expect(result[:charset]).to eq(["A"])
    end

    it "includes encoding from charstrings" do
      result = converter.send(:build_cff_font_dict, mock_type1_font)

      expect(result[:encoding]).to eq({ "A" => 1 })
    end
  end

  describe "#build_cff_private_dict" do
    let(:mock_private_dict) do
      dict = double("private_dict")
      allow(dict).to receive_messages(blue_values: [-20, 0, 750, 770],
                                      other_blues: [-250, -240], family_blues: [], family_other_blues: [], blue_scale: 0.039625, blue_shift: 7, blue_fuzz: 1, std_hw: 50, std_vw: 60, stem_snap_h: [50, 51], stem_snap_v: [60, 61], force_bold: false, language_group: 0, expansion_factor: 0.06, initial_random_seed: 0)
      dict
    end

    let(:mock_type1_font) do
      font = double("Type1Font")
      allow(font).to receive(:private_dict).and_return(mock_private_dict)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      font
    end

    it "builds CFF private dictionary hash" do
      result = converter.send(:build_cff_private_dict, mock_type1_font)

      expect(result).to be_a(Hash)
      expect(result[:blue_values]).to eq([-20, 0, 750, 770])
      expect(result[:blue_scale]).to eq(0.039625)
    end

    it "includes all hinting values" do
      result = converter.send(:build_cff_private_dict, mock_type1_font)

      expect(result[:std_hw]).to eq(50)
      expect(result[:std_vw]).to eq(60)
      expect(result[:stem_snap_h]).to eq([50, 51])
      expect(result[:stem_snap_v]).to eq([60, 61])
    end

    it "uses defaults when values are missing" do
      dict = double("private_dict")
      allow(dict).to receive_messages(blue_values: nil, other_blues: nil,
                                      family_blues: nil, family_other_blues: nil, blue_scale: nil, blue_shift: nil, blue_fuzz: nil, std_hw: nil, std_vw: nil, stem_snap_h: nil, stem_snap_v: nil, force_bold: nil, language_group: nil, expansion_factor: nil, initial_random_seed: nil)

      font = double("Type1Font")
      allow(font).to receive(:private_dict).and_return(dict)
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      result = converter.send(:build_cff_private_dict, font)

      expect(result[:blue_scale]).to eq(0.039625)
      expect(result[:blue_shift]).to eq(7)
      expect(result[:blue_fuzz]).to eq(1)
      expect(result[:force_bold]).to be false
    end
  end
end
