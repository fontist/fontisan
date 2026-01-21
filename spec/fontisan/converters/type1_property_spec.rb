# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Type 1 Property-Based Tests" do
  describe "SFNT table builder invariants" do
    let(:converter) { Fontisan::Converters::Type1Converter.new }

    # Property: Head table magic number is always 0x5F0F3CF5
    context "head table magic number invariant" do
      it "always produces correct magic number for any valid font bbox" do
        100.times do
          # Generate random font bbox
          font_bbox = [
            rand(-500..500),
            rand(-500..500),
            rand(500..1500),
            rand(500..1500),
          ]

          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(double("font_dict", font_bbox: font_bbox))
          allow(font).to receive(:version).and_return("001.000")
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          head_data = converter.send(:build_head_table, font)

          # Verify magic number
          magic = head_data[12..15].unpack1("N")
          expect(magic).to eq(0x5F0F3CF5), "Magic number should always be 0x5F0F3CF5"
        end
      end

      it "always uses 1000 units per em for Type 1 fonts" do
        100.times do
          font_dict = double("font_dict")
          allow(font_dict).to receive(:font_bbox).and_return([0, 0, 1000, 1000])

          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(font_dict)
          allow(font).to receive(:version).and_return("001.000")
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          head_data = converter.send(:build_head_table, font)

          # Verify units per em is 1000
          upem = head_data[18..19].unpack1("n")
          expect(upem).to eq(1000), "Units per em should always be 1000 for Type 1 fonts"
        end
      end
    end

    # Property: Maxp table version is 0.5 for CFF fonts
    context "maxp table version invariant" do
      it "always produces version 0.5 for any glyph count" do
        100.times do
          num_glyphs = rand(1..1000)

          font = double("Type1Font")
          allow(font).to receive(:charstrings).and_return(double("charstrings", count: num_glyphs))
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          maxp_data = converter.send(:build_maxp_table, font)

          # Verify version 0.5
          version = maxp_data[0..3].unpack1("N")
          expect(version).to eq(0x00005000), "Maxp version should always be 0.5 for CFF fonts"

          # Verify glyph count is preserved
          stored_count = maxp_data[4..5].unpack1("n")
          expect(stored_count).to eq(num_glyphs), "Glyph count should be preserved"
        end
      end
    end

    # Property: Weight class is always in range 100-900
    context "OS/2 weight class invariant" do
      it "always produces weight class in valid range" do
        # Test various weight names
        weight_names = [
          "Thin", "ExtraLight", "Light", "Regular", "Medium",
          "SemiBold", "Bold", "ExtraBold", "Black", "Heavy",
          "normal", "medium", "bold", "condensed", "expanded",
        ]

        weight_names.each do |weight_name|
          font_info = double("font_info")
          allow(font_info).to receive(:weight).and_return(weight_name)

          font_dict = double("font_dictionary")
          allow(font_dict).to receive(:font_bbox).and_return([0, 0, 1000, 1000])
          allow(font_dict).to receive(:font_info).and_return(font_info)

          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(font_dict)
          allow(font).to receive(:private_dict).and_return(nil)
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          os2_data = converter.send(:build_os2_table, font)
          weight_class = os2_data[4..5].unpack1("n")

          expect(weight_class).to be >= 100, "Weight class should be at least 100"
          expect(weight_class).to be <= 900, "Weight class should be at most 900"
        end
      end
    end

    # Property: Name table encoding is always UTF-16BE for Windows
    context "name table encoding invariant" do
      it "always uses Windows platform ID 3" do
        100.times do
          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(nil)
          allow(font).to receive(:font_name).and_return("TestFont")
          allow(font).to receive(:version).and_return("001.000")
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          name_data = converter.send(:build_name_table, font)

          # Verify platform ID is Windows (3)
          platform_id = name_data[6..7].unpack1("n")
          expect(platform_id).to eq(3), "Platform ID should always be Windows (3)"
        end
      end

      it "always uses Unicode BMP encoding ID 1" do
        100.times do
          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(nil)
          allow(font).to receive(:font_name).and_return("TestFont")
          allow(font).to receive(:version).and_return("001.000")
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          name_data = converter.send(:build_name_table, font)

          # Verify encoding ID is Unicode BMP (1)
          encoding_id = name_data[8..9].unpack1("n")
          expect(encoding_id).to eq(1), "Encoding ID should always be Unicode BMP (1)"
        end
      end

      it "always uses US English language ID 0x0409" do
        100.times do
          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(nil)
          allow(font).to receive(:font_name).and_return("TestFont")
          allow(font).to receive(:version).and_return("001.000")
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          name_data = converter.send(:build_name_table, font)

          # Verify language ID is US English (0x0409)
          language_id = name_data[10..11].unpack1("n")
          expect(language_id).to eq(0x0409), "Language ID should always be US English (0x0409)"
        end
      end
    end

    # Property: Post table version is 3.0 for CFF fonts
    context "post table version invariant" do
      it "always produces version 3.0 for any font" do
        100.times do
          font_info = double("font_info")
          allow(font_info).to receive(:italic_angle).and_return(0)
          allow(font_info).to receive(:underline_position).and_return(-100)
          allow(font_info).to receive(:underline_thickness).and_return(50)
          allow(font_info).to receive(:is_fixed_pitch).and_return(false)

          font_dict = double("font_dict")
          allow(font_dict).to receive(:font_info).and_return(font_info)

          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(font_dict)
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          post_data = converter.send(:build_post_table, font)

          # Verify version 3.0
          version = post_data[0..3].unpack1("N")
          expect(version).to eq(0x00030000), "Post table version should always be 3.0 for CFF fonts"
        end
      end

      it "always has fixed size of 32 bytes" do
        100.times do
          font_info = double("font_info")
          allow(font_info).to receive(:italic_angle).and_return(0)
          allow(font_info).to receive(:underline_position).and_return(-100)
          allow(font_info).to receive(:underline_thickness).and_return(50)
          allow(font_info).to receive(:is_fixed_pitch).and_return(false)

          font_dict = double("font_dict")
          allow(font_dict).to receive(:font_info).and_return(font_info)

          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(font_dict)
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          post_data = converter.send(:build_post_table, font)

          expect(post_data.bytesize).to eq(32), "Post table version 3.0 should always be 32 bytes"
        end
      end
    end

    # Property: Cmap table always has Windows BMP encoding
    context "cmap table encoding invariant" do
      it "always uses Windows platform (3) and Unicode BMP encoding (1)" do
        100.times do
          font = double("Type1Font")
          allow(font).to receive(:charstrings).and_return(double("charstrings", encoding: {}, glyph_names: []))
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          cmap_data = converter.send(:build_cmap_table, font)

          # Verify platform and encoding IDs
          platform_id = cmap_data[4..5].unpack1("n")
          encoding_id = cmap_data[6..7].unpack1("n")

          expect(platform_id).to eq(3), "Cmap should always use Windows platform"
          expect(encoding_id).to eq(1), "Cmap should always use Unicode BMP encoding"
        end
      end
    end
  end

  describe "CFF dictionary building invariants" do
    let(:converter) { Fontisan::Converters::Type1Converter.new }

    context "CFF font dictionary invariants" do
      it "always includes required fields" do
        100.times do
          font_bbox = [
            rand(-500..500),
            rand(-500..500),
            rand(500..1500),
            rand(500..1500),
          ]
          font_matrix = [0.001, 0, 0, 0.001, 0, 0]

          font_dict = double("font_dictionary")
          allow(font_dict).to receive(:version).and_return("001.000")
          allow(font_dict).to receive(:notice).and_return("Notice")
          allow(font_dict).to receive(:copyright).and_return("Copyright")
          allow(font_dict).to receive(:full_name).and_return("Test Font")
          allow(font_dict).to receive(:family_name).and_return("Test Family")
          allow(font_dict).to receive(:weight).and_return("Regular")
          allow(font_dict).to receive(:font_bbox).and_return(font_bbox)
          allow(font_dict).to receive(:font_matrix).and_return(font_matrix)
          allow(font_dict).to receive(:font_info).and_return(nil)

          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(font_dict)
          allow(font).to receive(:font_name).and_return("TestFont")
          allow(font).to receive(:charstrings).and_return(double("charstrings", encoding: { "A" => 1 }))
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          result = converter.send(:build_cff_font_dict, font)

          # Verify all required fields are present
          expect(result.key?(:version)).to be true
          expect(result.key?(:font_b_box)).to be true
          expect(result.key?(:font_matrix)).to be true
          expect(result.key?(:charset)).to be true
          expect(result.key?(:encoding)).to be true
        end
      end
    end

    context "CFF private dictionary invariants" do
      it "always uses valid default values" do
        100.times do
          font_dict = double("font_dictionary")
          allow(font_dict).to receive(:font_info).and_return(nil)

          private_dict = double("private_dict")
          allow(private_dict).to receive(:blue_values).and_return([])
          allow(private_dict).to receive(:other_blues).and_return([])
          allow(private_dict).to receive(:family_blues).and_return([])
          allow(private_dict).to receive(:family_other_blues).and_return([])
          allow(private_dict).to receive(:blue_scale).and_return(nil)
          allow(private_dict).to receive(:blue_shift).and_return(nil)
          allow(private_dict).to receive(:blue_fuzz).and_return(nil)
          allow(private_dict).to receive(:force_bold).and_return(nil)
          allow(private_dict).to receive(:std_hw).and_return(nil)
          allow(private_dict).to receive(:std_vw).and_return(nil)
          allow(private_dict).to receive(:stem_snap_h).and_return(nil)
          allow(private_dict).to receive(:stem_snap_v).and_return(nil)
          allow(private_dict).to receive(:language_group).and_return(nil)
          allow(private_dict).to receive(:expansion_factor).and_return(nil)
          allow(private_dict).to receive(:initial_random_seed).and_return(nil)

          font = double("Type1Font")
          allow(font).to receive(:private_dict).and_return(private_dict)
          allow(font).to receive(:font_dictionary).and_return(font_dict)
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          result = converter.send(:build_cff_private_dict, font)

          # Verify defaults are applied
          expect(result[:blue_scale]).to eq(0.039625), "Blue scale should have default value"
          expect(result[:blue_shift]).to eq(7), "Blue shift should have default value"
          expect(result[:blue_fuzz]).to eq(1), "Blue fuzz should have default value"
          expect(result[:force_bold]).to eq(false), "Force bold should default to false"
        end
      end
    end
  end

  describe "Round-trip invariants" do
    let(:converter) { Fontisan::Converters::Type1Converter.new }

    # Property: Version format parsing is reversible
    context "version parsing invariant" do
      it "correctly parses and re-encodes version strings" do
        versions = [
          "001.000",
          "002.500",
          "010.000",
          "1.0",
          "2.5",
          "10.0",
        ]

        versions.each do |version_str|
          font_dict = double("font_dict")
          allow(font_dict).to receive(:font_bbox).and_return([0, 0, 1000, 1000])

          font = double("Type1Font")
          allow(font).to receive(:font_dictionary).and_return(font_dict)
          allow(font).to receive(:version).and_return(version_str)
          allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

          head_data = converter.send(:build_head_table, font)

          # Extract version from head table and verify it matches
          version_raw = head_data[0..3].unpack1("N")
          reconstructed = (version_raw >> 16) + ((version_raw & 0xFFFF) / 65_536.0)

          # Parse original version
          parts = version_str.split(".")
          original_major = parts[0].to_i
          original_minor = parts[1]&.to_i || 0
          original = original_major + (original_minor / 1000.0)

          # Should be approximately equal (allowing for floating point precision)
          expect(reconstructed.round(3)).to eq(original.round(3))
        end
      end
    end
  end
end
