# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Type 1 Font Conversion Integration" do
  describe "Type 1 to OTF conversion" do
    let(:converter) { Fontisan::Converters::Type1Converter.new }

    # Since Type1Font loading is not fully implemented yet,
    # we test the SFNT table builders with mock data

    context "SFNT table building" do
      let(:mock_font_dict) do
        dict = double("font_dictionary")
        allow(dict).to receive(:font_bbox).and_return([50, -200, 950, 800])
        allow(dict).to receive(:font_name).and_return("TestFont")
        allow(dict).to receive(:family_name).and_return("TestFamily")
        allow(dict).to receive(:full_name).and_return("TestFont Regular")
        allow(dict).to receive(:weight).and_return("Regular")
        allow(dict).to receive(:font_info).and_return(mock_font_info)
        dict
      end

      let(:mock_font_info) do
        info = double("font_info")
        allow(info).to receive(:version).and_return("001.000")
        allow(info).to receive(:copyright).and_return("Copyright 2024")
        allow(info).to receive(:notice).and_return("Test Font")
        allow(info).to receive(:family_name).and_return("TestFamily")
        allow(info).to receive(:full_name).and_return("TestFont Regular")
        allow(info).to receive(:weight).and_return("Regular")
        allow(info).to receive(:italic_angle).and_return(0)
        allow(info).to receive(:underline_position).and_return(-100)
        allow(info).to receive(:underline_thickness).and_return(50)
        allow(info).to receive(:is_fixed_pitch).and_return(false)
        info
      end

      let(:mock_private_dict) do
        dict = double("private_dict")
        allow(dict).to receive(:blue_values).and_return([-20, 0, 750, 770])
        allow(dict).to receive(:other_blues).and_return([-250, -240])
        dict
      end

      let(:mock_charstrings) do
        cs = double("charstrings")
        allow(cs).to receive(:count).and_return(250)
        allow(cs).to receive(:encoding).and_return({
          ".notdef" => 0,
          "A" => 1,
          "B" => 2,
        })
        allow(cs).to receive(:glyph_names).and_return([".notdef", "A", "B"])
        cs
      end

      let(:mock_type1_font) do
        font = double("Type1Font")
        allow(font).to receive(:font_dictionary).and_return(mock_font_dict)
        allow(font).to receive(:private_dict).and_return(mock_private_dict)
        allow(font).to receive(:charstrings).and_return(mock_charstrings)
        allow(font).to receive(:font_name).and_return("TestFont")
        allow(font).to receive(:version).and_return("001.000")
        allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
        font
      end

      it "builds all required SFNT tables" do
        tables = {
          "head" => converter.send(:build_head_table, mock_type1_font),
          "hhea" => converter.send(:build_hhea_table, mock_type1_font),
          "maxp" => converter.send(:build_maxp_table, mock_type1_font),
          "name" => converter.send(:build_name_table, mock_type1_font),
          "OS/2" => converter.send(:build_os2_table, mock_type1_font),
          "post" => converter.send(:build_post_table, mock_type1_font),
          "cmap" => converter.send(:build_cmap_table, mock_type1_font),
        }

        # Note: CFF table is built by OutlineConverter, not by individual table builders
        expect(tables.keys.sort).to eq(["OS/2", "cmap", "head", "hhea", "maxp", "name", "post"])
      end

      it "produces valid head table" do
        head_data = converter.send(:build_head_table, mock_type1_font)

        expect(head_data).to be_a(String)
        expect(head_data.bytesize).to be >= 54

        # Verify magic number
        magic = head_data[12..15].unpack1("N")
        expect(magic).to eq(0x5F0F3CF5)

        # Verify units per em
        upem = head_data[18..19].unpack1("n")
        expect(upem).to eq(1000)
      end

      it "produces valid hhea table" do
        hhea_data = converter.send(:build_hhea_table, mock_type1_font)

        expect(hhea_data).to be_a(String)
        expect(hhea_data.bytesize).to be >= 36

        # Verify version
        version = hhea_data[0..3].unpack1("N")
        expect(version).to eq(0x00010000)
      end

      it "produces valid maxp table" do
        maxp_data = converter.send(:build_maxp_table, mock_type1_font)

        expect(maxp_data).to be_a(String)
        expect(maxp_data.bytesize).to eq(6)

        # Verify version 0.5 for CFF fonts
        version = maxp_data[0..3].unpack1("N")
        expect(version).to eq(0x00005000)
      end

      it "produces valid name table" do
        name_data = converter.send(:build_name_table, mock_type1_font)

        expect(name_data).to be_a(String)
        expect(name_data.bytesize).to be >= 6

        # Verify format selector
        format = name_data[0..1].unpack1("n")
        expect(format).to eq(0)
      end

      it "produces valid OS/2 table" do
        os2_data = converter.send(:build_os2_table, mock_type1_font)

        expect(os2_data).to be_a(String)
        expect(os2_data.bytesize).to be >= 78

        # Verify version
        version = os2_data[0..1].unpack1("n")
        expect(version).to eq(4)
      end

      it "produces valid post table" do
        post_data = converter.send(:build_post_table, mock_type1_font)

        expect(post_data).to be_a(String)
        expect(post_data.bytesize).to eq(32)

        # Verify version 3.0 for CFF fonts
        version = post_data[0..3].unpack1("N")
        expect(version).to eq(0x00030000)
      end

      it "produces valid cmap table" do
        cmap_data = converter.send(:build_cmap_table, mock_type1_font)

        expect(cmap_data).to be_a(String)
        expect(cmap_data.bytesize).to be >= 12

        # Verify encoding record
        platform_id = cmap_data[4..5].unpack1("n")
        expect(platform_id).to eq(3)
      end
    end

    context "CFF dictionary building" do
      let(:mock_font_info) do
        info = double("font_info")
        allow(info).to receive(:version).and_return("001.000")
        allow(info).to receive(:notice).and_return("Copyright notice")
        allow(info).to receive(:copyright).and_return("Copyright 2024")
        allow(info).to receive(:full_name).and_return("TestFont")
        allow(info).to receive(:family_name).and_return("TestFamily")
        allow(info).to receive(:weight).and_return("Regular")
        info
      end

      let(:mock_font_dict) do
        dict = double("font_dictionary")
        allow(dict).to receive(:version).and_return("001.000")
        allow(dict).to receive(:notice).and_return("Copyright notice")
        allow(dict).to receive(:copyright).and_return("Copyright 2024")
        allow(dict).to receive(:full_name).and_return("TestFont")
        allow(dict).to receive(:family_name).and_return("TestFamily")
        allow(dict).to receive(:weight).and_return("Regular")
        allow(dict).to receive(:font_bbox).and_return([0, -100, 1000, 900])
        allow(dict).to receive(:font_matrix).and_return([0.001, 0, 0, 0.001, 0, 0])
        allow(dict).to receive(:font_info).and_return(mock_font_info)
        dict
      end

      let(:mock_private_dict) do
        dict = double("private_dict")
        allow(dict).to receive(:blue_values).and_return([-20, 0, 750, 770])
        allow(dict).to receive(:other_blues).and_return([-250, -240])
        allow(dict).to receive(:family_blues).and_return([])
        allow(dict).to receive(:family_other_blues).and_return([])
        allow(dict).to receive(:blue_scale).and_return(0.039625)
        allow(dict).to receive(:blue_shift).and_return(7)
        allow(dict).to receive(:blue_fuzz).and_return(1)
        allow(dict).to receive(:std_hw).and_return(50)
        allow(dict).to receive(:std_vw).and_return(60)
        allow(dict).to receive(:stem_snap_h).and_return([50, 51])
        allow(dict).to receive(:stem_snap_v).and_return([60, 61])
        allow(dict).to receive(:force_bold).and_return(false)
        allow(dict).to receive(:language_group).and_return(0)
        allow(dict).to receive(:expansion_factor).and_return(0.06)
        allow(dict).to receive(:initial_random_seed).and_return(0)
        dict
      end

      let(:mock_charstrings) do
        cs = double("charstrings")
        allow(cs).to receive(:encoding).and_return({ "A" => 1 })
        cs
      end

      let(:mock_type1_font) do
        font = double("Type1Font")
        allow(font).to receive(:font_dictionary).and_return(mock_font_dict)
        allow(font).to receive(:private_dict).and_return(mock_private_dict)
        allow(font).to receive(:font_name).and_return("TestFont")
        allow(font).to receive(:charstrings).and_return(mock_charstrings)
        allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
        font
      end

      it "builds CFF font dictionary" do
        font_dict = converter.send(:build_cff_font_dict, mock_type1_font)

        expect(font_dict[:version]).to eq("001.000")
        expect(font_dict[:full_name]).to eq("TestFont")
        expect(font_dict[:family_name]).to eq("TestFamily")
        expect(font_dict[:font_b_box]).to eq([0, -100, 1000, 900])
        expect(font_dict[:font_matrix]).to eq([0.001, 0, 0, 0.001, 0, 0])
      end

      it "builds CFF private dictionary" do
        private_dict = converter.send(:build_cff_private_dict, mock_type1_font)

        expect(private_dict[:blue_values]).to eq([-20, 0, 750, 770])
        expect(private_dict[:blue_scale]).to eq(0.039625)
        expect(private_dict[:blue_shift]).to eq(7)
        expect(private_dict[:std_hw]).to eq(50)
        expect(private_dict[:std_vw]).to eq(60)
      end
    end

    context "error handling" do
      let(:mock_font) do
        font = double("Type1Font")
        allow(font).to receive(:font_dictionary).and_return(nil)
        allow(font).to receive(:private_dict).and_return(nil)
        allow(font).to receive(:charstrings).and_return(nil)
        allow(font).to receive(:font_name).and_return("TestFont")
        allow(font).to receive(:version).and_return("001.000")
        allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
        font
      end

      it "handles missing font dictionary gracefully" do
        expect { converter.send(:build_head_table, mock_font) }.not_to raise_error
        expect { converter.send(:build_hhea_table, mock_font) }.not_to raise_error
        expect { converter.send(:build_name_table, mock_font) }.not_to raise_error
      end

      it "handles missing charstrings gracefully" do
        expect { converter.send(:build_maxp_table, mock_font) }.not_to raise_error
        expect { converter.send(:build_hhea_table, mock_font) }.not_to raise_error
        expect { converter.send(:build_cmap_table, mock_font) }.not_to raise_error
      end
    end

    context "weight class mapping" do
      let(:mock_font_dict) do
        dict = double("font_dictionary")
        allow(dict).to receive(:font_bbox).and_return([0, 0, 1000, 1000])
        dict
      end

      let(:mock_type1_font) do
        font = double("Type1Font")
        allow(font).to receive(:font_dictionary).and_return(mock_font_dict)
        allow(font).to receive(:private_dict).and_return(nil)
        allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
        font
      end

      it "maps weight names to correct OS/2 weight classes" do
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
          "Heavy" => 900,
        }

        weights.each do |weight_name, expected_class|
          font_info = double("font_info")
          allow(font_info).to receive(:weight).and_return(weight_name)
          allow(mock_font_dict).to receive(:font_info).and_return(font_info)

          os2_data = converter.send(:build_os2_table, mock_type1_font)
          weight_class = os2_data[4..5].unpack1("n")

          expect(weight_class).to eq(expected_class), "#{weight_name} should map to #{expected_class}"
        end
      end
    end

    context "integration with FormatConverter" do
      let(:mock_type1_font) do
        font = double("Type1Font")
        allow(font).to receive(:font_dictionary).and_return(nil)
        allow(font).to receive(:private_dict).and_return(nil)
        allow(font).to receive(:charstrings).and_return(nil)
        allow(font).to receive(:font_name).and_return("TestFont")
        allow(font).to receive(:version).and_return("001.000")
        allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
        font
      end

      it "supports Type 1 to OTF conversion" do
        format_converter = Fontisan::Converters::FormatConverter.new

        expect(format_converter.supported?(:type1, :otf)).to be true
        expect(format_converter.supported_targets(:type1)).to include(:otf)
      end

      it "detects Type 1 format correctly" do
        format_converter = Fontisan::Converters::FormatConverter.new

        detected = format_converter.send(:detect_format, mock_type1_font)
        expect(detected).to eq(:type1)
      end
    end
  end
end
