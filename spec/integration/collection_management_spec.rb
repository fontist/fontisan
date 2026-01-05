# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe "Collection Management Integration", :integration do
  let(:font1_path) do
    font_fixture_path("MonaSans", "fonts/static/ttf/MonaSans-Regular.ttf")
  end
  let(:font2_path) do
    font_fixture_path("MonaSans", "fonts/static/ttf/MonaSans-Bold.ttf")
  end
  let(:temp_dir) { Dir.mktmpdir }
  let(:collection_path) { File.join(temp_dir, "test.ttc") }
  let(:extract_dir) { File.join(temp_dir, "extracted") }

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "TTC creation with real fonts" do
    it "creates valid TTC from multiple fonts" do
      # Load fonts
      font1 = Fontisan::FontLoader.load(font1_path)
      font2 = Fontisan::FontLoader.load(font2_path)

      # Build collection
      builder = Fontisan::Collection::Builder.new([font1, font2], format: :ttc)
      result = builder.build_to_file(collection_path)

      # Verify result
      expect(File.exist?(collection_path)).to be true
      expect(result[:num_fonts]).to eq(2)
      expect(result[:space_savings]).to be >= 0
      expect(result[:output_size]).to be > 0
    end

    it "saves space through table sharing" do
      font1 = Fontisan::FontLoader.load(font1_path)
      font2 = Fontisan::FontLoader.load(font2_path)

      builder = Fontisan::Collection::Builder.new([font1, font2])
      result = builder.build_to_file(collection_path)

      # Collection should be smaller than sum of individual fonts
      individual_size = File.size(font1_path) + File.size(font2_path)
      collection_size = result[:output_size]

      expect(collection_size).to be < individual_size
      expect(result[:space_savings]).to be > 0
    end

    it "creates readable TTC file" do
      font1 = Fontisan::FontLoader.load(font1_path)
      font2 = Fontisan::FontLoader.load(font2_path)

      builder = Fontisan::Collection::Builder.new([font1, font2])
      builder.build_to_file(collection_path)

      # Verify TTC can be read
      File.open(collection_path, "rb") do |io|
        ttc = Fontisan::TrueTypeCollection.read(io)
        expect(ttc.num_fonts).to eq(2)
        expect(ttc.valid?).to be true
      end
    end
  end

  describe "round-trip: pack then unpack" do
    it "preserves font integrity through pack/unpack cycle" do
      # Step 1: Pack fonts into collection
      font1 = Fontisan::FontLoader.load(font1_path)
      font2 = Fontisan::FontLoader.load(font2_path)

      builder = Fontisan::Collection::Builder.new([font1, font2])
      builder.build_to_file(collection_path)

      expect(File.exist?(collection_path)).to be true

      # Step 2: Unpack collection
      command = Fontisan::Commands::UnpackCommand.new(
        collection_path,
        output_dir: extract_dir,
      )
      unpack_result = command.run

      expect(unpack_result[:fonts_extracted]).to eq(2)
      expect(unpack_result[:extracted_files].size).to eq(2)

      # Step 3: Verify extracted fonts are valid
      unpack_result[:extracted_files].each do |extracted_path|
        expect(File.exist?(extracted_path)).to be true
        expect(File.size(extracted_path)).to be > 0

        # Should be loadable
        extracted_font = Fontisan::FontLoader.load(extracted_path)
        expect(extracted_font).not_to be_nil
        expect(extracted_font.valid?).to be true
      end
    end

    it "preserves essential table data" do
      # Pack
      font1 = Fontisan::FontLoader.load(font1_path)
      original_head = font1.table("head")
      original_hhea = font1.table("hhea")

      font2 = Fontisan::FontLoader.load(font2_path)
      builder = Fontisan::Collection::Builder.new([font1, font2])
      builder.build_to_file(collection_path)

      # Unpack
      command = Fontisan::Commands::UnpackCommand.new(
        collection_path,
        output_dir: extract_dir,
        font_index: 0,
      )
      result = command.run

      # Load extracted font and verify tables
      extracted_font = Fontisan::FontLoader.load(result[:extracted_files].first)
      extracted_head = extracted_font.table("head")
      extracted_hhea = extracted_font.table("hhea")

      # Verify key values preserved
      expect(extracted_head.units_per_em).to eq(original_head.units_per_em)
      expect(extracted_hhea.ascent).to eq(original_hhea.ascent)
      expect(extracted_hhea.descent).to eq(original_hhea.descent)
    end
  end

  describe "table sharing optimization" do
    it "identifies shared tables correctly" do
      font1 = Fontisan::FontLoader.load(font1_path)
      font2 = Fontisan::FontLoader.load(font2_path)

      builder = Fontisan::Collection::Builder.new([font1, font2])
      analysis = builder.analyze

      # Should find at least some shared tables in font family
      expect(analysis[:shared_tables]).not_to be_empty
      expect(analysis[:space_savings]).to be > 0
    end

    it "reports accurate sharing statistics" do
      font1 = Fontisan::FontLoader.load(font1_path)
      font2 = Fontisan::FontLoader.load(font2_path)

      builder = Fontisan::Collection::Builder.new([font1, font2])
      result = builder.build

      stats = result[:statistics]
      expect(stats[:total_tables]).to be > 0
      expect(stats[:sharing_percentage]).to be >= 0
      expect(stats[:sharing_percentage]).to be <= 100
    end
  end

  describe "validation" do
    it "rejects single font" do
      font1 = Fontisan::FontLoader.load(font1_path) if File.exist?(font1_path)

      expect do
        builder = Fontisan::Collection::Builder.new([font1])
        builder.validate!
      end.to raise_error(Fontisan::Error, /requires at least 2 fonts/)
    end

    it "validates font has required tables" do
      font1 = Fontisan::FontLoader.load(font1_path)
      font2 = Fontisan::FontLoader.load(font2_path)

      builder = Fontisan::Collection::Builder.new([font1, font2])
      expect { builder.validate! }.not_to raise_error
    end
  end

  describe "format options" do
    it "creates TTC format" do
      font1 = Fontisan::FontLoader.load(font1_path)
      font2 = Fontisan::FontLoader.load(font2_path)

      builder = Fontisan::Collection::Builder.new([font1, font2], format: :ttc)
      result = builder.build_to_file(collection_path)

      expect(result[:format]).to eq(:ttc)

      # Verify signature
      File.open(collection_path, "rb") do |io|
        signature = io.read(4)
        expect(signature).to eq("ttcf")
      end
    end

    it "creates OTC format" do
      font1 = Fontisan::FontLoader.load(font1_path)
      font2 = Fontisan::FontLoader.load(font2_path)

      otc_path = File.join(temp_dir, "test.otc")
      builder = Fontisan::Collection::Builder.new([font1, font2], format: :otc)
      result = builder.build_to_file(otc_path)

      expect(result[:format]).to eq(:otc)

      # OTC also uses ttcf signature
      File.open(otc_path, "rb") do |io|
        signature = io.read(4)
        expect(signature).to eq("ttcf")
      end
    end
  end

  describe "loading TTC collections with multiple fonts" do
    let(:dina_path) { font_fixture_path("DinaRemasterII", "DinaRemasterII.ttc") }

    it "loads DinaRemasterII.ttc collection successfully" do
      collection = Fontisan::FontLoader.load_collection(dina_path)

      expect(collection).to be_a(Fontisan::TrueTypeCollection)
      expect(collection.num_fonts).to eq(2)
      expect(collection.valid?).to be true
    end

    it "loads individual fonts from DinaRemasterII.ttc" do
      # Load first font (Medium)
      font0 = Fontisan::FontLoader.load(dina_path, font_index: 0)
      expect(font0).to be_a(Fontisan::TrueTypeFont)
      expect(font0.valid?).to be true

      name_table = font0.table("name")
      expect(name_table.english_name(1)).to eq("DinaRemasterII") # Family

      # Load second font (Bold)
      font1 = Fontisan::FontLoader.load(dina_path, font_index: 1)
      expect(font1).to be_a(Fontisan::TrueTypeFont)
      expect(font1.valid?).to be true
    end

    it "lists fonts in DinaRemasterII.ttc collection" do
      File.open(dina_path, "rb") do |io|
        ttc = Fontisan::TrueTypeCollection.read(io)
        list = ttc.list_fonts(io)

        expect(list.num_fonts).to eq(2)
        expect(list.fonts.size).to eq(2)
        expect(list.fonts[0].family_name).to eq("DinaRemasterII")
        expect(list.fonts[0].font_format).to eq("TrueType")
        expect(list.fonts[1].font_format).to eq("TrueType")
      end
    end
  end

  describe "loading OpenType Collection with many fonts" do
    let(:noto_path) { font_fixture_path("NotoSerifCJK", "NotoSerifCJK.ttc") }

    it "loads NotoSerifCJK.ttc collection with proper type detection" do
      collection = Fontisan::FontLoader.load_collection(noto_path)

      expect(collection).to be_a(Fontisan::OpenTypeCollection)
      expect(collection.num_fonts).to eq(35)
      expect(collection.valid?).to be true
    end

    it "loads individual OpenType fonts from large collection" do
      # Test first font
      font0 = Fontisan::FontLoader.load(noto_path, font_index: 0)
      expect(font0).to be_a(Fontisan::OpenTypeFont)
      expect(font0.valid?).to be true

      # Test last font
      font34 = Fontisan::FontLoader.load(noto_path, font_index: 34)
      expect(font34).to be_a(Fontisan::OpenTypeFont)
      expect(font34.valid?).to be true
    end

    it "scans all 35 fonts for correct type detection" do
      File.open(noto_path, "rb") do |io|
        otc = Fontisan::OpenTypeCollection.read(io)
        list = otc.list_fonts(io)

        expect(list.num_fonts).to eq(35)
        expect(list.fonts.size).to eq(35)

        # All fonts should be OpenType format
        list.fonts.each do |font_summary|
          expect(font_summary.font_format).to eq("OpenType")
        end
      end
    end
  end
end
