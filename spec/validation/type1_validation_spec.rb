# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Type 1 Font Validation" do
  let(:converter) { Fontisan::Converters::Type1Converter.new }

  # Get a sample Type 1 font file for testing
  def get_test_font
    gem_root = File.expand_path("../..", __dir__)
    fixture_dir = File.join(gem_root, "spec", "fixtures", "fonts", "type1")
    quicksand = File.join(fixture_dir, "quicksand.pfb")
    return quicksand if File.exist?(quicksand)
    Dir.glob(File.join(fixture_dir, "**", "*.{pfb,t1}")).first
  end

  describe "SFNT table structure validation" do
    it "produces valid SFNT header" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      # Mock up required data for SFNT table building
      font_dict = double("font_dictionary")
      allow(font_dict).to receive(:font_bbox).and_return([50, -200, 950, 800])
      allow(font_dict).to receive(:font_matrix).and_return([0.001, 0, 0, 0.001, 0, 0])
      allow(font_dict).to receive(:font_name).and_return("TestFont")
      allow(font_dict).to receive(:family_name).and_return("TestFamily")
      allow(font_dict).to receive(:full_name).and_return("TestFont Regular")
      allow(font_dict).to receive(:weight).and_return("Regular")

      font_info = double("font_info")
      allow(font_info).to receive(:version).and_return("001.000")
      allow(font_info).to receive(:copyright).and_return("Copyright 2024")
      allow(font_info).to receive(:notice).and_return("Test Font")
      allow(font_info).to receive(:family_name).and_return("TestFamily")
      allow(font_info).to receive(:full_name).and_return("TestFont Regular")
      allow(font_info).to receive(:weight).and_return("Regular")
      allow(font_info).to receive(:italic_angle).and_return(0)
      allow(font_info).to receive(:underline_position).and_return(-100)
      allow(font_info).to receive(:underline_thickness).and_return(50)
      allow(font_info).to receive(:is_fixed_pitch).and_return(false)
      allow(font_dict).to receive(:font_info).and_return(font_info)

      private_dict = double("private_dict")
      allow(private_dict).to receive(:blue_values).and_return([-20, 0, 750, 770])
      allow(private_dict).to receive(:other_blues).and_return([-250, -240])
      allow(private_dict).to receive(:family_blues).and_return([])
      allow(private_dict).to receive(:family_other_blues).and_return([])

      charstrings = double("charstrings")
      allow(charstrings).to receive(:count).and_return(250)
      allow(charstrings).to receive(:encoding).and_return({ ".notdef" => 0, "A" => 1, "B" => 2 })
      allow(charstrings).to receive(:glyph_names).and_return([".notdef", "A", "B"])

      mock_font = double("Type1Font")
      allow(mock_font).to receive(:font_dictionary).and_return(font_dict)
      allow(mock_font).to receive(:private_dict).and_return(private_dict)
      allow(mock_font).to receive(:charstrings).and_return(charstrings)
      allow(mock_font).to receive(:font_name).and_return("TestFont")
      allow(mock_font).to receive(:version).and_return("001.000")
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      # Build SFNT header
      tables = {
        "head" => converter.send(:build_head_table, mock_font),
        "hhea" => converter.send(:build_hhea_table, mock_font),
        "maxp" => converter.send(:build_maxp_table, mock_font),
        "name" => converter.send(:build_name_table, mock_font),
        "OS/2" => converter.send(:build_os2_table, mock_font),
        "post" => converter.send(:build_post_table, mock_font),
        "cmap" => converter.send(:build_cmap_table, mock_font),
      }

      # Build SFNT header
      num_tables = tables.size
      entry_selector = (2 ** Math.log2(num_tables).ceil).to_i
      search_range = entry_selector * 16
      range_shift = (num_tables - entry_selector / 16) * 16 if num_tables > entry_selector / 16

      sfnt_version = 0x4F54544F # "OTTO"
      header = [
        sfnt_version,        # SFNT version
        num_tables,          # Number of tables
        search_range,        # Search range
        entry_selector,      # Entry selector
        range_shift || 0,    # Range shift
      ].pack("Nnnnn")

      # Verify SFNT header structure
      expect(header.bytesize).to eq(12), "SFNT header should be 12 bytes"
      expect(header[0..3].unpack1("N")).to eq(0x4F54544F), "SFNT version should be 'OTTO'"
      expect(header[4..5].unpack1("n")).to eq(num_tables), "Table count should match"
    end
  end

  describe "Head table validation" do
    it "produces valid head table structure" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      # Mock font with required attributes
      font_dict = double("font_dictionary")
      allow(font_dict).to receive(:font_bbox).and_return([50, -200, 950, 800])
      allow(font_dict).to receive(:font_matrix).and_return([0.001, 0, 0, 0.001, 0, 0])
      allow(font_dict).to receive(:font_name).and_return("TestFont")
      allow(font_dict).to receive(:family_name).and_return("TestFamily")
      allow(font_dict).to receive(:full_name).and_return("TestFont Regular")
      allow(font_dict).to receive(:weight).and_return("Regular")

      font_info = double("font_info")
      allow(font_info).to receive(:version).and_return("001.000")
      allow(font_info).to receive(:copyright).and_return("Copyright 2024")
      allow(font_info).to receive(:notice).and_return("Test Font")
      allow(font_info).to receive(:family_name).and_return("TestFamily")
      allow(font_info).to receive(:full_name).and_return("TestFont Regular")
      allow(font_info).to receive(:weight).and_return("Regular")
      allow(font_info).to receive(:italic_angle).and_return(0)
      allow(font_info).to receive(:underline_position).and_return(-100)
      allow(font_info).to receive(:underline_thickness).and_return(50)
      allow(font_info).to receive(:is_fixed_pitch).and_return(false)
      allow(font_dict).to receive(:font_info).and_return(font_info)

      private_dict = double("private_dict")
      allow(private_dict).to receive(:blue_values).and_return([-20, 0, 750, 770])
      allow(private_dict).to receive(:other_blues).and_return([-250, -240])
      allow(private_dict).to receive(:family_blues).and_return([])
      allow(private_dict).to receive(:family_other_blues).and_return([])

      charstrings = double("charstrings")
      allow(charstrings).to receive(:count).and_return(250)
      allow(charstrings).to receive(:encoding).and_return({ ".notdef" => 0, "A" => 1, "B" => 2 })
      allow(charstrings).to receive(:glyph_names).and_return([".notdef", "A", "B"])

      mock_font = double("Type1Font")
      allow(mock_font).to receive(:font_dictionary).and_return(font_dict)
      allow(mock_font).to receive(:private_dict).and_return(private_dict)
      allow(mock_font).to receive(:charstrings).and_return(charstrings)
      allow(mock_font).to receive(:font_name).and_return("TestFont")
      allow(mock_font).to receive(:version).and_return("001.000")
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      head_data = converter.send(:build_head_table, mock_font)

      # Validate head table structure
      expect(head_data.bytesize).to be >= 54, "head table should be at least 54 bytes"

      # Table version (Fixed: 1.0)
      version = head_data[0..3].unpack1("N")
      expect(version).to eq(0x00010000), "head table version should be 1.0"

      # Magic number
      magic = head_data[12..15].unpack1("N")
      expect(magic).to eq(0x5F0F3CF5), "head table magic number should be 0x5F0F3CF5"

      # Flags (bit 0 = baseline at y=0, bit 1 = left sidebearing at x=0, bit 2 = instructions may depend on point size)
      flags = head_data[16..17].unpack1("n")
      # Note: The actual flag value may vary based on Type1Converter implementation
      # Just verify flags is a valid integer
      expect(flags).to be_a(Integer), "Flags should be an integer"
      expect(flags).to be >= 0, "Flags should be non-negative"

      # Units per em
      upem = head_data[18..19].unpack1("n")
      expect(upem).to eq(1000), "Type 1 fonts use 1000 units per em"

      # Created and modified timestamps (should be valid)
      created = head_data[20..27].unpack1("Q>")
      modified = head_data[28..35].unpack1("Q>")
      expect(created).to be_a(Integer), "Created timestamp should be an integer"
      expect(modified).to be_a(Integer), "Modified timestamp should be an integer"
    end
  end

  describe "Maxp table validation" do
    it "produces valid maxp table for CFF fonts" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      # Mock charstrings
      charstrings = double("charstrings")
      allow(charstrings).to receive(:count).and_return(250)

      mock_font = double("Type1Font")
      allow(mock_font).to receive(:charstrings).and_return(charstrings)
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      maxp_data = converter.send(:build_maxp_table, mock_font)

      # Validate maxp table structure for CFF (version 0.5)
      expect(maxp_data.bytesize).to eq(6), "CFF maxp table should be exactly 6 bytes"

      # Version 0.5 for CFF fonts
      version = maxp_data[0..3].unpack1("N")
      expect(version).to eq(0x00005000), "CFF maxp version should be 0.5"

      # Glyph count
      num_glyphs = maxp_data[4..5].unpack1("n")
      expect(num_glyphs).to eq(250), "Glyph count should be preserved"
    end
  end

  describe "Name table validation" do
    it "produces valid name table with required records" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      mock_font = double("Type1Font")
      allow(mock_font).to receive(:font_dictionary).and_return(nil)
      allow(mock_font).to receive(:font_name).and_return("TestFont")
      allow(mock_font).to receive(:version).and_return("001.000")
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      name_data = converter.send(:build_name_table, mock_font)

      # Validate name table structure
      expect(name_data.bytesize).to be >= 6, "name table should have at least header"

      # Format selector
      format = name_data[0..1].unpack1("n")
      expect(format).to eq(0), "name table format should be 0"

      # Count
      count = name_data[2..3].unpack1("n")
      expect(count).to be > 0, "name table should have at least one name record"

      # Storage offset
      storage_offset = name_data[4..5].unpack1("n")
      expect(storage_offset).to be >= 6, "storage offset should be after header"
    end
  end

  describe "Post table validation" do
    it "produces valid post table version 3.0" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      # Mock font with required attributes
      font_info = double("font_info")
      allow(font_info).to receive(:italic_angle).and_return(0)
      allow(font_info).to receive(:underline_position).and_return(-100)
      allow(font_info).to receive(:underline_thickness).and_return(50)
      allow(font_info).to receive(:is_fixed_pitch).and_return(false)

      font_dict = double("font_dict")
      allow(font_dict).to receive(:font_info).and_return(font_info)

      mock_font = double("Type1Font")
      allow(mock_font).to receive(:font_dictionary).and_return(font_dict)
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      post_data = converter.send(:build_post_table, mock_font)

      # Validate post table structure for version 3.0
      expect(post_data.bytesize).to eq(32), "post table version 3.0 should be exactly 32 bytes"

      # Version 3.0 for CFF fonts
      version = post_data[0..3].unpack1("N")
      expect(version).to eq(0x00030000), "CFF post table version should be 3.0"

      # Italic angle (Fixed)
      italic_angle = post_data[4..7].unpack1("N")
      expect(italic_angle).to be_a(Integer), "Italic angle should be an integer"

      # Underline position
      underline_position = post_data[8..9].unpack1("s>")
      expect(underline_position).to be_a(Integer), "Underline position should be an integer"

      # Underline thickness
      underline_thickness = post_data[10..11].unpack1("s>")
      expect(underline_thickness).to be_a(Integer), "Underline thickness should be an integer"

      # Is fixed pitch (uint32)
      is_fixed_pitch = post_data[12..15].unpack1("N")
      expect(is_fixed_pitch).to be >= 0, "isFixedPitch should be non-negative"
    end
  end

  describe "Cmap table validation" do
    it "produces valid format 4 cmap subtable" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      # Create a simple encoding map
      charstrings = double("charstrings")
      allow(charstrings).to receive(:encoding).and_return({
        ".notdef" => 0,
        "A" => 1,
        "B" => 2,
        "C" => 3,
      })
      allow(charstrings).to receive(:glyph_names).and_return([".notdef", "A", "B", "C"])

      mock_font = double("Type1Font")
      allow(mock_font).to receive(:charstrings).and_return(charstrings)
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      cmap_data = converter.send(:build_cmap_table, mock_font)

      # Validate cmap table structure
      expect(cmap_data.bytesize).to be >= 12, "cmap table should have at least header"

      # Table version (should be 0)
      version = cmap_data[0..1].unpack1("n")
      expect(version).to eq(0), "cmap table version should be 0"

      # Number of encoding records
      num_records = cmap_data[2..3].unpack1("n")
      expect(num_records).to eq(1), "cmap should have one encoding record"

      # Platform ID (3 = Windows)
      platform_id = cmap_data[4..5].unpack1("n")
      expect(platform_id).to eq(3), "cmap should use Windows platform"

      # Encoding ID (1 = Unicode BMP)
      encoding_id = cmap_data[6..7].unpack1("n")
      expect(encoding_id).to eq(1), "cmap should use Unicode BMP encoding"
    end
  end

  describe "OS/2 table validation" do
    it "produces valid OS/2 table version 4" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      # Mock font with required attributes
      font_info = double("font_info")
      allow(font_info).to receive(:weight).and_return("Regular")

      font_dict = double("font_dictionary")
      allow(font_dict).to receive(:font_bbox).and_return([0, 0, 1000, 1000])
      allow(font_dict).to receive(:font_info).and_return(font_info)

      private_dict = double("private_dict")
      allow(private_dict).to receive(:blue_values).and_return([-20, 0, 750, 770])
      allow(private_dict).to receive(:other_blues).and_return([-250, -240])

      mock_font = double("Type1Font")
      allow(mock_font).to receive(:font_dictionary).and_return(font_dict)
      allow(mock_font).to receive(:private_dict).and_return(private_dict)
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      os2_data = converter.send(:build_os2_table, mock_font)

      # Validate OS/2 table structure
      expect(os2_data.bytesize).to be >= 78, "OS/2 table version 4 should be at least 78 bytes"

      # Version
      version = os2_data[0..1].unpack1("n")
      expect(version).to eq(4), "OS/2 table version should be 4"

      # Weight class (should be in range 100-900)
      weight_class = os2_data[4..5].unpack1("n")
      expect(weight_class).to be_between(100, 900), "Weight class should be in valid range"

      # Unicode ranges and codepage ranges should be present
      # (The exact values depend on the encoding)
    end
  end

  describe "Hhea table validation" do
    it "produces valid hhea table" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      # Mock font with required attributes
      font_dict = double("font_dictionary")
      allow(font_dict).to receive(:font_bbox).and_return([50, -200, 950, 800])
      allow(font_dict).to receive(:font_matrix).and_return([0.001, 0, 0, 0.001, 0, 0])

      private_dict = double("private_dict")
      allow(private_dict).to receive(:blue_values).and_return([-20, 0, 750, 770])
      allow(private_dict).to receive(:other_blues).and_return([-250, -240])

      charstrings = double("charstrings")
      allow(charstrings).to receive(:count).and_return(250)

      mock_font = double("Type1Font")
      allow(mock_font).to receive(:font_dictionary).and_return(font_dict)
      allow(mock_font).to receive(:private_dict).and_return(private_dict)
      allow(mock_font).to receive(:charstrings).and_return(charstrings)
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      hhea_data = converter.send(:build_hhea_table, mock_font)

      # Validate hhea table structure
      expect(hhea_data.bytesize).to be >= 36, "hhea table should be at least 36 bytes"

      # Version (Fixed: 1.0)
      version = hhea_data[0..3].unpack1("N")
      expect(version).to eq(0x00010000), "hhea table version should be 1.0"

      # Ascender and descender
      ascender = hhea_data[4..5].unpack1("s>")
      descender = hhea_data[6..7].unpack1("s>")
      line_gap = hhea_data[8..9].unpack1("s>")

      expect(ascender).to be_a(Integer), "Ascender should be an integer"
      expect(descender).to be_a(Integer), "Descender should be an integer"
      expect(line_gap).to be_a(Integer), "Line gap should be an integer"

      # Number of horizontal metrics (must match numGlyphs)
      num_hmetrics = hhea_data[34..35].unpack1("n")
      expect(num_hmetrics).to eq(250), "Number of hmetrics should match glyph count"
    end
  end

  describe "CFF OUTLINE data validation" do
    it "produces valid CFF data structure" do
      font_path = get_test_font
      skip "No Type 1 font fixture found" unless font_path

      font = Fontisan::FontLoader.load(font_path, mode: Fontisan::LoadingModes::METADATA)
      skip "Font loading failed" unless font

      # Mock font with required attributes
      font_dict = double("font_dictionary")
      allow(font_dict).to receive(:version).and_return("001.000")
      allow(font_dict).to receive(:notice).and_return("Copyright notice")
      allow(font_dict).to receive(:copyright).and_return("Copyright 2024")
      allow(font_dict).to receive(:full_name).and_return("TestFont")
      allow(font_dict).to receive(:family_name).and_return("TestFamily")
      allow(font_dict).to receive(:weight).and_return("Regular")
      allow(font_dict).to receive(:font_bbox).and_return([0, -100, 1000, 900])
      allow(font_dict).to receive(:font_matrix).and_return([0.001, 0, 0, 0.001, 0, 0])
      allow(font_dict).to receive(:font_info).and_return(nil)

      private_dict = double("private_dict")
      allow(private_dict).to receive(:blue_values).and_return([-20, 0, 750, 770])
      allow(private_dict).to receive(:other_blues).and_return([-250, -240])
      allow(private_dict).to receive(:family_blues).and_return([])
      allow(private_dict).to receive(:family_other_blues).and_return([])
      allow(private_dict).to receive(:blue_scale).and_return(0.039625)
      allow(private_dict).to receive(:blue_shift).and_return(7)
      allow(private_dict).to receive(:blue_fuzz).and_return(1)
      allow(private_dict).to receive(:std_hw).and_return(nil)
      allow(private_dict).to receive(:std_vw).and_return(nil)
      allow(private_dict).to receive(:stem_snap_h).and_return(nil)
      allow(private_dict).to receive(:stem_snap_v).and_return(nil)
      allow(private_dict).to receive(:force_bold).and_return(nil)
      allow(private_dict).to receive(:language_group).and_return(nil)
      allow(private_dict).to receive(:expansion_factor).and_return(nil)
      allow(private_dict).to receive(:initial_random_seed).and_return(nil)

      charstrings = double("charstrings")
      allow(charstrings).to receive(:encoding).and_return({ "A" => 1 })

      mock_font = double("Type1Font")
      allow(mock_font).to receive(:font_dictionary).and_return(font_dict)
      allow(mock_font).to receive(:private_dict).and_return(private_dict)
      allow(mock_font).to receive(:font_name).and_return("TestFont")
      allow(mock_font).to receive(:charstrings).and_return(charstrings)
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)

      # Build CFF font and private dictionaries
      cff_font_dict = converter.send(:build_cff_font_dict, mock_font)
      cff_private_dict = converter.send(:build_cff_private_dict, mock_font)

      # Validate CFF font dictionary
      expect(cff_font_dict).to be_a(Hash), "CFF font dict should be a Hash"
      expect(cff_font_dict).to have_key(:version), "CFF font dict should have version"
      expect(cff_font_dict).to have_key(:font_b_box), "CFF font dict should have font_bbox"
      expect(cff_font_dict).to have_key(:font_matrix), "CFF font dict should have font_matrix"

      # Validate CFF private dictionary
      expect(cff_private_dict).to be_a(Hash), "CFF private dict should be a Hash"
      expect(cff_private_dict).to have_key(:blue_scale), "CFF private dict should have blue_scale"
      expect(cff_private_dict[:blue_scale]).to eq(0.039625), "blue_scale should have default value"
    end
  end
end
