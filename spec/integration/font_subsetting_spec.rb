# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Font Subsetting Integration" do
  let(:font_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::TrueTypeFont.from_file(font_path) }
  let(:output_dir) { Dir.mktmpdir("fontisan_subset_test") }

  after do
    FileUtils.rm_rf(output_dir) if Dir.exist?(output_dir)
  end

  describe "Basic subsetting workflow" do
    it "subsets font to specific text" do
      output_path = File.join(output_dir, "text_subset.ttf")

      # Build subset
      glyph_ids = text_to_glyph_ids(font, "Hello World!")
      options = Fontisan::Subset::Options.new(profile: "pdf")
      builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      # Verify output
      expect(File.exist?(output_path)).to be true
      expect(File.size(output_path)).to be > 1000
      expect(File.size(output_path)).to be < File.size(font_path)

      # Load and verify subset font
      subset_font = Fontisan::TrueTypeFont.from_file(output_path)
      expect(subset_font).to be_a(Fontisan::TrueTypeFont)

      # Verify glyph count
      subset_maxp = subset_font.table("maxp")
      expect(subset_maxp.num_glyphs).to be < font.table("maxp").num_glyphs
      expect(subset_maxp.num_glyphs).to be >= glyph_ids.size
    end

    it "produces valid font that can be re-loaded" do
      output_path = File.join(output_dir, "reloadable_subset.ttf")

      glyph_ids = [0, 65, 66, 67] # .notdef, A, B, C
      builder = Fontisan::Subset::Builder.new(font, glyph_ids, {})

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      # Reload and verify
      subset_font = Fontisan::TrueTypeFont.from_file(output_path)

      # Verify essential tables exist
      expect(subset_font.table("head")).not_to be_nil
      expect(subset_font.table("maxp")).not_to be_nil
      expect(subset_font.table("hhea")).not_to be_nil
      expect(subset_font.table("hmtx")).not_to be_nil
      expect(subset_font.table("cmap")).not_to be_nil
    end
  end

  describe "Profile-based subsetting" do
    let(:glyph_ids) { [0, 65, 66, 67] }

    it "creates PDF-optimized subset" do
      output_path = File.join(output_dir, "pdf_subset.ttf")

      options = Fontisan::Subset::Options.new(profile: "pdf")
      builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      subset_font = Fontisan::TrueTypeFont.from_file(output_path)

      # Verify PDF profile tables are present
      expect(subset_font.table("cmap")).not_to be_nil
      expect(subset_font.table("glyf")).not_to be_nil
      expect(subset_font.table("loca")).not_to be_nil
    end

    it "creates web-optimized subset" do
      output_path = File.join(output_dir, "web_subset.ttf")

      options = Fontisan::Subset::Options.new(profile: "web")
      builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      subset_font = Fontisan::TrueTypeFont.from_file(output_path)

      # Verify web profile includes OS/2 table
      expect(subset_font.table("OS/2")).not_to be_nil
    end

    it "creates minimal subset" do
      output_path = File.join(output_dir, "minimal_subset.ttf")

      options = Fontisan::Subset::Options.new(profile: "minimal")
      builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      subset_font = Fontisan::TrueTypeFont.from_file(output_path)

      # Verify minimal profile has required tables
      expect(subset_font.table("cmap")).not_to be_nil
      expect(subset_font.table("head")).not_to be_nil
      expect(subset_font.table("maxp")).not_to be_nil
    end
  end

  describe "Composite glyph handling" do
    it "includes component glyphs automatically" do
      # Find a composite glyph (if available)
      accessor = Fontisan::GlyphAccessor.new(font)

      # Test with first 100 glyphs
      base_glyphs = (0..100).to_a
      accessor.closure_for(base_glyphs)

      # Build subset
      output_path = File.join(output_dir, "composite_subset.ttf")
      builder = Fontisan::Subset::Builder.new(font, base_glyphs, {})

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      # Verify closure was calculated
      expect(builder.closure.size).to be >= base_glyphs.size

      # Verify font is valid
      subset_font = Fontisan::TrueTypeFont.from_file(output_path)
      expect(subset_font.table("maxp").num_glyphs).to eq(builder.mapping.size)
    end
  end

  describe "Glyph ID mapping modes" do
    let(:glyph_ids) { [0, 10, 20, 30] }

    it "creates compact mapping by default" do
      output_path = File.join(output_dir, "compact_subset.ttf")

      options = Fontisan::Subset::Options.new(retain_gids: false)
      builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      # Verify compact mapping
      expect(builder.mapping.new_id(0)).to eq(0)
      expect(builder.mapping.new_id(10)).to be < 10
      expect(builder.mapping.size).to be <= glyph_ids.size + 5 # Allow for closure
    end

    it "retains original glyph IDs when requested" do
      output_path = File.join(output_dir, "retained_subset.ttf")

      options = Fontisan::Subset::Options.new(retain_gids: true)
      builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      # Verify retained mapping
      glyph_ids.each do |old_id|
        expect(builder.mapping.new_id(old_id)).to eq(old_id)
      end
    end
  end

  describe "Subsetting options" do
    let(:glyph_ids) { [0, 65, 66, 67] }

    it "drops glyph names when requested" do
      output_path = File.join(output_dir, "no_names_subset.ttf")

      options = Fontisan::Subset::Options.new(drop_names: true)
      builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      subset_font = Fontisan::TrueTypeFont.from_file(output_path)
      post = subset_font.table("post")

      # Post version 3.0 has no glyph names
      version = post.to_binary_s[0, 4].unpack1("N")
      expect(version).to eq(0x00030000)
    end

    it "handles multiple options simultaneously" do
      output_path = File.join(output_dir, "multi_option_subset.ttf")

      options = Fontisan::Subset::Options.new(
        profile: "web",
        drop_names: true,
        retain_gids: false,
      )
      builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)

      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      # Verify font is valid
      subset_font = Fontisan::TrueTypeFont.from_file(output_path)
      expect(subset_font.table("head")).not_to be_nil
    end
  end

  describe "Character set subsetting" do
    it "subsets to Latin alphabet" do
      output_path = File.join(output_dir, "latin_subset.ttf")

      # A-Z, a-z
      text = ("A".."Z").to_a.join + ("a".."z").to_a.join
      glyph_ids = text_to_glyph_ids(font, text)

      builder = Fontisan::Subset::Builder.new(font, glyph_ids, {})
      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      subset_font = Fontisan::TrueTypeFont.from_file(output_path)

      # Verify subset is smaller
      expect(File.size(output_path)).to be < File.size(font_path)

      # Verify cmap still works
      cmap = subset_font.table("cmap")
      expect(cmap.unicode_mappings).not_to be_empty
    end

    it "subsets to digits" do
      output_path = File.join(output_dir, "digits_subset.ttf")

      glyph_ids = text_to_glyph_ids(font, "0123456789")

      builder = Fontisan::Subset::Builder.new(font, glyph_ids, {})
      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      subset_font = Fontisan::TrueTypeFont.from_file(output_path)
      maxp = subset_font.table("maxp")

      # Should have minimal glyphs (.notdef + digits + any composites)
      expect(maxp.num_glyphs).to be <= 15
    end
  end

  describe "Font validation" do
    let(:glyph_ids) { [0, 65, 66, 67] }

    it "produces font with valid sfnt header" do
      output_path = File.join(output_dir, "valid_header_subset.ttf")

      builder = Fontisan::Subset::Builder.new(font, glyph_ids, {})
      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      # Verify sfnt header
      header = subset_binary[0, 12]
      sfnt_version, num_tables, search_range, =
        header.unpack("N n n n n")

      expect(sfnt_version).to eq(0x00010000) # TrueType version
      expect(num_tables).to be > 0
      expect(search_range % 16).to eq(0)
    end

    it "produces font with correct table checksums" do
      output_path = File.join(output_dir, "valid_checksums_subset.ttf")

      builder = Fontisan::Subset::Builder.new(font, glyph_ids, {})
      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      # Load and verify - FontLoader will fail if checksums are invalid
      expect do
        Fontisan::TrueTypeFont.from_file(output_path)
      end.not_to raise_error
    end

    it "produces font with aligned table data" do
      output_path = File.join(output_dir, "aligned_subset.ttf")

      builder = Fontisan::Subset::Builder.new(font, glyph_ids, {})
      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      # Parse table directory
      num_tables = subset_binary[4, 2].unpack1("n")
      offset = 12

      # Check each table offset is 4-byte aligned
      num_tables.times do
        entry = subset_binary[offset, 16]
        _tag, _checksum, table_offset, _length = entry.unpack("a4 N N N")

        expect(table_offset % 4).to eq(0), "Table offset not 4-byte aligned"
        offset += 16
      end
    end
  end

  describe "Edge cases and error recovery" do
    it "handles empty glyph set gracefully" do
      # Should raise error for empty glyph set
      expect do
        Fontisan::Subset::Builder.new(font, [], {}).build
      end.to raise_error(ArgumentError, /At least one glyph/)
    end

    it "handles only .notdef glyph" do
      output_path = File.join(output_dir, "notdef_only_subset.ttf")

      builder = Fontisan::Subset::Builder.new(font, [0], {})
      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      subset_font = Fontisan::TrueTypeFont.from_file(output_path)
      expect(subset_font.table("maxp").num_glyphs).to be >= 1
    end

    it "handles large subset gracefully" do
      output_path = File.join(output_dir, "large_subset.ttf")

      # Subset to first 500 glyphs
      maxp = font.table("maxp")
      num_glyphs = [maxp.num_glyphs, 500].min
      glyph_ids = (0...num_glyphs).to_a

      builder = Fontisan::Subset::Builder.new(font, glyph_ids, {})
      subset_binary = builder.build
      File.binwrite(output_path, subset_binary)

      subset_font = Fontisan::TrueTypeFont.from_file(output_path)
      expect(subset_font).to be_a(Fontisan::TrueTypeFont)
    end
  end

  describe "CLI command integration" do
    it "creates subset via CLI command" do
      output_path = File.join(output_dir, "cli_subset.ttf")

      options = {
        text: "Hello World",
        output: output_path,
        profile: "pdf",
      }

      command = Fontisan::Commands::SubsetCommand.new(font_path, options)
      result = command.run

      expect(result[:output]).to eq(output_path)
      expect(File.exist?(output_path)).to be true

      # Verify subset font
      subset_font = Fontisan::TrueTypeFont.from_file(output_path)
      expect(subset_font).to be_a(Fontisan::TrueTypeFont)
    end
  end

  private

  # Helper to convert text to glyph IDs
  def text_to_glyph_ids(font, text)
    cmap = font.table("cmap")
    mappings = cmap.unicode_mappings

    glyph_ids = Set.new([0]) # Always include .notdef

    text.each_char do |char|
      glyph_id = mappings[char.ord]
      glyph_ids.add(glyph_id) if glyph_id
    end

    glyph_ids.to_a
  end
end
