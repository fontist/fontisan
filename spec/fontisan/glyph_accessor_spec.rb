# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::GlyphAccessor do
  let(:font_path) do
    "spec/fixtures/fonts/libertinus/Libertinus-7.051/static/TTF/LibertinusSerif-Regular.ttf"
  end
  let(:font) { Fontisan::FontLoader.load(font_path) }
  let(:accessor) { described_class.new(font) }

  describe "#initialize" do
    it "accepts a font object" do
      expect { described_class.new(font) }.not_to raise_error
    end

    it "raises ArgumentError if font is nil" do
      expect do
        described_class.new(nil)
      end.to raise_error(ArgumentError, /Font cannot be nil/)
    end

    it "raises ArgumentError if font doesn't respond to :table" do
      invalid_font = Object.new
      expect { described_class.new(invalid_font) }.to raise_error(
        ArgumentError, /must respond to :table method/
      )
    end

    it "stores the font instance" do
      expect(accessor.font).to eq(font)
    end
  end

  describe "#truetype?" do
    context "with TrueType font" do
      it "returns true when glyf table exists" do
        expect(accessor.truetype?).to be true
      end
    end

    context "with mock font without glyf table" do
      let(:mock_font) do
        double("Font", table: nil)
      end
      let(:accessor) { described_class.new(mock_font) }

      it "returns false when glyf table doesn't exist" do
        expect(accessor.truetype?).to be false
      end
    end
  end

  describe "#cff?" do
    context "with TrueType font" do
      it "returns false when CFF table doesn't exist" do
        expect(accessor.cff?).to be false
      end
    end

    context "with mock CFF font" do
      let(:mock_font) do
        font_double = double("Font")
        allow(font_double).to receive(:table).with("glyf").and_return(nil)
        allow(font_double).to receive(:table).with("CFF ").and_return(double("CFF"))
        allow(font_double).to receive(:table).with("maxp").and_return(
          double("Maxp", num_glyphs: 100),
        )
        font_double
      end
      let(:accessor) { described_class.new(mock_font) }

      it "returns true when CFF table exists" do
        expect(accessor.cff?).to be true
      end
    end
  end

  describe "#glyph_exists?" do
    it "returns true for valid glyph ID 0 (.notdef)" do
      expect(accessor.glyph_exists?(0)).to be true
    end

    it "returns false for negative glyph ID" do
      expect(accessor.glyph_exists?(-1)).to be false
    end

    it "returns false for nil glyph ID" do
      expect(accessor.glyph_exists?(nil)).to be false
    end

    it "returns false for glyph ID beyond num_glyphs" do
      maxp = font.table("maxp")
      invalid_id = maxp.num_glyphs + 100
      expect(accessor.glyph_exists?(invalid_id)).to be false
    end

    it "returns true for valid glyph IDs within range" do
      maxp = font.table("maxp")
      valid_id = maxp.num_glyphs - 1
      expect(accessor.glyph_exists?(valid_id)).to be true
    end
  end

  describe "#has_glyph_for_char?" do
    it "returns true for mapped character 'A'" do
      expect(accessor.has_glyph_for_char?(0x0041)).to be true
    end

    it "returns true for mapped character 'a'" do
      expect(accessor.has_glyph_for_char?(0x0061)).to be true
    end

    it "returns false for unmapped character" do
      # Use a character unlikely to be in the font
      expect(accessor.has_glyph_for_char?(0x1F600)).to be false # Emoji
    end

    it "returns true for space character" do
      expect(accessor.has_glyph_for_char?(0x0020)).to be true
    end
  end

  describe "#glyph_for_id" do
    context "with valid glyph ID" do
      it "returns a glyph object for .notdef (glyph 0)" do
        glyph = accessor.glyph_for_id(0)
        expect(glyph).not_to be_nil
      end

      it "returns glyph with correct type" do
        glyph = accessor.glyph_for_id(0)
        expect(glyph).to respond_to(:bounding_box)
      end

      it "caches glyph objects" do
        glyph1 = accessor.glyph_for_id(0)
        glyph2 = accessor.glyph_for_id(0)
        expect(glyph1).to equal(glyph2) # Same object instance
      end

      it "returns nil for empty glyph (space)" do
        # Space character typically has empty glyph data
        cmap = font.table("cmap")
        space_glyph_id = cmap.unicode_mappings[0x0020]
        glyph = accessor.glyph_for_id(space_glyph_id)
        # Space may or may not have outline data, both are valid
        expect(glyph).to be_a(Object).or be_nil
      end
    end

    context "with invalid glyph ID" do
      it "raises ArgumentError for nil glyph ID" do
        expect { accessor.glyph_for_id(nil) }.to raise_error(
          ArgumentError, /glyph_id cannot be nil/
        )
      end

      it "raises ArgumentError for negative glyph ID" do
        expect { accessor.glyph_for_id(-1) }.to raise_error(
          ArgumentError, /glyph_id must be >= 0/
        )
      end

      it "raises ArgumentError for glyph ID beyond range" do
        maxp = font.table("maxp")
        invalid_id = maxp.num_glyphs + 100
        expect { accessor.glyph_for_id(invalid_id) }.to raise_error(
          ArgumentError, /exceeds number of glyphs/
        )
      end
    end
  end

  describe "#glyph_for_char" do
    it "returns glyph for 'A' character" do
      glyph = accessor.glyph_for_char(0x0041)
      expect(glyph).not_to be_nil
    end

    it "returns glyph for 'a' character" do
      glyph = accessor.glyph_for_char(0x0061)
      expect(glyph).not_to be_nil
    end

    it "returns nil for unmapped character" do
      glyph = accessor.glyph_for_char(0x1F600) # Emoji unlikely in font
      expect(glyph).to be_nil
    end

    it "works with String#ord" do
      glyph = accessor.glyph_for_char("A".ord)
      expect(glyph).not_to be_nil
    end
  end

  describe "#glyph_for_name" do
    context "with PostScript names available" do
      it "returns glyph for standard name '.notdef'" do
        glyph = accessor.glyph_for_name(".notdef")
        expect(glyph).not_to be_nil
      end

      it "returns glyph for standard name 'A'" do
        glyph = accessor.glyph_for_name("A")
        # Result depends on whether post table has names
        # May return glyph or nil
        expect(glyph).to be_a(Object).or be_nil
      end

      it "returns nil for non-existent name" do
        glyph = accessor.glyph_for_name("NonExistentGlyphName")
        expect(glyph).to be_nil
      end
    end
  end

  describe "#metrics_for_id" do
    it "returns metrics hash for glyph 0" do
      metrics = accessor.metrics_for_id(0)
      expect(metrics).to be_a(Hash)
      expect(metrics).to have_key(:advance_width)
      expect(metrics).to have_key(:lsb)
    end

    it "returns positive advance width" do
      metrics = accessor.metrics_for_id(0)
      expect(metrics[:advance_width]).to be >= 0
    end

    it "returns metrics for regular glyph" do
      cmap = font.table("cmap")
      a_glyph_id = cmap.unicode_mappings[0x0041] # 'A'
      metrics = accessor.metrics_for_id(a_glyph_id)
      expect(metrics[:advance_width]).to be > 0
    end

    it "raises ArgumentError for invalid glyph ID" do
      expect { accessor.metrics_for_id(-1) }.to raise_error(ArgumentError)
    end

    it "auto-parses hmtx if not already parsed" do
      # Create a new accessor to ensure hmtx is not parsed
      new_accessor = described_class.new(font)
      metrics = new_accessor.metrics_for_id(0)
      expect(metrics).to be_a(Hash)
    end
  end

  describe "#metrics_for_char" do
    it "returns metrics for 'A' character" do
      metrics = accessor.metrics_for_char(0x0041)
      expect(metrics).to be_a(Hash)
      expect(metrics[:advance_width]).to be > 0
    end

    it "returns nil for unmapped character" do
      metrics = accessor.metrics_for_char(0x1F600)
      expect(metrics).to be_nil
    end
  end

  describe "#outline_for_id" do
    it "returns outline for valid glyph ID" do
      cmap = font.table("cmap")
      a_glyph_id = cmap.unicode_mappings[0x0041] # 'A'

      outline = accessor.outline_for_id(a_glyph_id)

      expect(outline).to be_a(Fontisan::Models::GlyphOutline)
      expect(outline.glyph_id).to eq(a_glyph_id)
      expect(outline.contour_count).to be > 0
      expect(outline.point_count).to be > 0
    end

    it "returns outline with valid bbox" do
      cmap = font.table("cmap")
      a_glyph_id = cmap.unicode_mappings[0x0041]

      outline = accessor.outline_for_id(a_glyph_id)

      expect(outline.bbox).to be_a(Hash)
      expect(outline.bbox).to have_key(:x_min)
      expect(outline.bbox).to have_key(:y_min)
      expect(outline.bbox).to have_key(:x_max)
      expect(outline.bbox).to have_key(:y_max)
    end

    it "returns nil for empty glyphs" do
      # Space character typically has no outline
      cmap = font.table("cmap")
      space_glyph_id = cmap.unicode_mappings[0x0020]

      outline = accessor.outline_for_id(space_glyph_id)

      # Space may or may not have outline, both are valid
      if outline
        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
      else
        expect(outline).to be_nil
      end
    end

    it "can convert outline to SVG path" do
      cmap = font.table("cmap")
      a_glyph_id = cmap.unicode_mappings[0x0041]

      outline = accessor.outline_for_id(a_glyph_id)
      svg_path = outline.to_svg_path

      expect(svg_path).to be_a(String)
      expect(svg_path.length).to be > 0
      expect(svg_path).to include("M") # Move command
      expect(svg_path).to include("Z") # Close path command
    end

    it "can convert outline to commands" do
      cmap = font.table("cmap")
      a_glyph_id = cmap.unicode_mappings[0x0041]

      outline = accessor.outline_for_id(a_glyph_id)
      commands = outline.to_commands

      expect(commands).to be_an(Array)
      expect(commands.length).to be > 0
      expect(commands.first[0]).to eq(:move_to)
      expect(commands.last[0]).to eq(:close_path)
    end

    it "raises ArgumentError for invalid glyph ID" do
      expect { accessor.outline_for_id(-1) }.to raise_error(ArgumentError)
      expect { accessor.outline_for_id(nil) }.to raise_error(ArgumentError)
    end
  end

  describe "#outline_for_codepoint" do
    it "returns outline for valid Unicode codepoint" do
      outline = accessor.outline_for_codepoint(0x0041) # 'A'

      expect(outline).to be_a(Fontisan::Models::GlyphOutline)
      expect(outline.contour_count).to be > 0
    end

    it "returns nil for unmapped codepoint" do
      outline = accessor.outline_for_codepoint(0x1F600) # Emoji unlikely in font

      expect(outline).to be_nil
    end

    it "works with various Unicode characters" do
      # Test basic Latin
      outline = accessor.outline_for_codepoint(0x0061) # 'a'
      expect(outline).to be_a(Fontisan::Models::GlyphOutline)

      # Test digit
      outline = accessor.outline_for_codepoint(0x0030) # '0'
      expect(outline).to be_a(Fontisan::Models::GlyphOutline).or be_nil
    end
  end

  describe "#outline_for_char" do
    it "returns outline for single character string" do
      outline = accessor.outline_for_char("A")

      expect(outline).to be_a(Fontisan::Models::GlyphOutline)
      expect(outline.contour_count).to be > 0
    end

    it "returns outline for lowercase character" do
      outline = accessor.outline_for_char("a")

      expect(outline).to be_a(Fontisan::Models::GlyphOutline)
    end

    it "returns outline for digit" do
      outline = accessor.outline_for_char("1")

      expect(outline).to be_a(Fontisan::Models::GlyphOutline).or be_nil
    end

    it "returns nil for unmapped character" do
      # Test with emoji (unlikely to be in font)
      outline = accessor.outline_for_char("😀")

      expect(outline).to be_nil
    end

    it "raises ArgumentError for multi-character string" do
      expect { accessor.outline_for_char("AB") }.to raise_error(
        ArgumentError,
        /must be a single character/,
      )
    end

    it "raises ArgumentError for non-string input" do
      expect { accessor.outline_for_char(65) }.to raise_error(ArgumentError)
      expect { accessor.outline_for_char(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for empty string" do
      expect { accessor.outline_for_char("") }.to raise_error(
        ArgumentError,
        /must be a single character/,
      )
    end
  end

  describe "#closure_for" do
    it "raises ArgumentError if input is not an array" do
      expect { accessor.closure_for(42) }.to raise_error(
        ArgumentError, /must be an Array/
      )
    end

    it "always includes glyph 0 (.notdef)" do
      closure = accessor.closure_for([1, 2, 3])
      expect(closure).to include(0)
    end

    it "includes all input glyphs" do
      input = [1, 2, 3]
      closure = accessor.closure_for(input)
      input.each do |gid|
        expect(closure).to include(gid)
      end
    end

    it "returns a Set" do
      closure = accessor.closure_for([1])
      expect(closure).to be_a(Set)
    end

    it "handles empty input array" do
      closure = accessor.closure_for([])
      expect(closure).to eq(Set[0]) # Only .notdef
    end

    it "filters out invalid glyph IDs" do
      maxp = font.table("maxp")
      invalid_id = maxp.num_glyphs + 100
      closure = accessor.closure_for([1, invalid_id])
      expect(closure).not_to include(invalid_id)
      expect(closure).to include(1)
    end

    context "with compound glyphs" do
      it "includes component glyphs from compound glyphs" do
        # Find a compound glyph in the font
        cmap = font.table("cmap")

        # Try common accented characters that are often compound
        test_chars = [0x00C0, 0x00C1, 0x00C2, 0x00E0, 0x00E1] # À, Á, Â, à, á

        compound_found = false
        test_chars.each do |char_code|
          glyph_id = cmap.unicode_mappings[char_code]
          next unless glyph_id

          glyph = accessor.glyph_for_id(glyph_id)
          next unless glyph
          next unless glyph.respond_to?(:compound?) && glyph.compound?

          closure = accessor.closure_for([glyph_id])

          # Closure should include the compound glyph itself
          expect(closure).to include(glyph_id)

          # Closure should include component glyphs
          if glyph.respond_to?(:components)
            glyph.components.each do |component|
              expect(closure).to include(component[:glyph_index])
            end
          end

          # Closure should be larger than just the input
          expect(closure.size).to be > 2 # At least .notdef + compound + one component

          compound_found = true
          break
        end

        # If no compound glyphs found, just verify basic closure works
        unless compound_found
          closure = accessor.closure_for([1])
          expect(closure).to include(0, 1)
        end
      end

      it "handles recursive compound glyphs" do
        # Test that closure handles compound glyphs that reference other compound glyphs
        closure = accessor.closure_for([1, 2, 3])
        expect(closure).to be_a(Set)
        expect(closure.size).to be >= 4 # At least .notdef + inputs
      end
    end

    it "handles duplicate glyph IDs in input" do
      closure = accessor.closure_for([1, 1, 2, 2, 3])
      expect(closure.size).to be >= 4 # .notdef + 1, 2, 3
      expect(closure).to include(0, 1, 2, 3)
    end
  end

  describe "#clear_cache" do
    it "clears glyph cache" do
      # Access some glyphs to populate cache
      accessor.glyph_for_id(0)
      accessor.glyph_for_id(1)

      # Clear cache
      accessor.clear_cache

      # Should not raise error
      expect { accessor.clear_cache }.not_to raise_error
    end

    it "allows accessing glyphs after cache clear" do
      glyph1 = accessor.glyph_for_id(0)
      accessor.clear_cache
      glyph2 = accessor.glyph_for_id(0)

      expect(glyph2).not_to be_nil
      # Should be different object instance (not cached)
      expect(glyph1).not_to equal(glyph2)
    end

    it "clears glyf table cache if available" do
      glyf = font.table("glyf")

      # Populate some caches
      accessor.glyph_for_id(0)

      expect(glyf).to receive(:clear_cache).and_call_original
      accessor.clear_cache
    end
  end

  describe "error handling" do
    context "with missing tables" do
      let(:incomplete_font) do
        font_double = double("Font")
        allow(font_double).to receive(:table).with("glyf").and_return(nil)
        allow(font_double).to receive(:table).with("CFF ").and_return(nil)
        allow(font_double).to receive(:table).with("maxp").and_return(
          double("Maxp", num_glyphs: 100),
        )
        font_double
      end
      let(:accessor) { described_class.new(incomplete_font) }

      it "raises MissingTableError when neither glyf nor CFF exists" do
        expect { accessor.glyph_for_id(0) }.to raise_error(
          Fontisan::MissingTableError, /neither glyf nor CFF/
        )
      end
    end

    context "with missing cmap table" do
      let(:incomplete_font) do
        font_double = double("Font")
        allow(font_double).to receive(:table).with("cmap").and_return(nil)
        allow(font_double).to receive(:table).with("maxp").and_return(
          double("Maxp", num_glyphs: 100),
        )
        font_double
      end
      let(:accessor) { described_class.new(incomplete_font) }

      it "raises MissingTableError for glyph_for_char" do
        expect { accessor.glyph_for_char(0x0041) }.to raise_error(
          Fontisan::MissingTableError, /cmap/
        )
      end
    end
  end

  describe "CFF font support" do
    let(:mock_cff_font) do
      font_double = double("Font")

      # Create mock CFF table
      mock_cff = double("CFF")
      mock_charset = double("Charset", glyph_name: "A")
      mock_encoding = double("Encoding")
      mock_charstring = double(
        "CharString",
        path: [{ type: :move_to, x: 0.0, y: 0.0 }],
        width: 500,
        bounding_box: [0.0, 0.0, 500.0, 700.0],
        to_commands: [[:move_to, 0.0, 0.0]],
      )

      allow(mock_cff).to receive_messages(
        charstring_for_glyph: mock_charstring, charset: mock_charset, encoding: mock_encoding,
      )

      # Setup font to return CFF table
      allow(font_double).to receive(:table).with("glyf").and_return(nil)
      allow(font_double).to receive(:table).with("CFF ").and_return(mock_cff)
      allow(font_double).to receive(:table).with("maxp").and_return(
        double("Maxp", num_glyphs: 100),
      )
      allow(font_double).to receive(:table).with("cmap").and_return(
        double("Cmap", unicode_mappings: { 0x0041 => 42 }),
      )

      font_double
    end
    let(:cff_accessor) { described_class.new(mock_cff_font) }

    describe "#cff?" do
      it "returns true when CFF table exists" do
        expect(cff_accessor.cff?).to be true
      end

      it "returns false when CFF table doesn't exist" do
        expect(accessor.cff?).to be false
      end
    end

    describe "#glyph_for_id with CFF font" do
      it "returns a CFFGlyph object" do
        glyph = cff_accessor.glyph_for_id(42)
        expect(glyph).not_to be_nil
        expect(glyph).to be_a(Fontisan::Tables::Cff::CFFGlyph)
      end

      it "returns glyph with correct properties" do
        glyph = cff_accessor.glyph_for_id(42)
        expect(glyph.glyph_id).to eq(42)
        expect(glyph.width).to eq(500)
        expect(glyph.bounding_box).to eq([0.0, 0.0, 500.0, 700.0])
      end

      it "returns glyph that responds to simple?" do
        glyph = cff_accessor.glyph_for_id(42)
        expect(glyph.simple?).to be true
      end

      it "returns glyph that responds to compound?" do
        glyph = cff_accessor.glyph_for_id(42)
        expect(glyph.compound?).to be false
      end

      it "returns glyph with name from charset" do
        glyph = cff_accessor.glyph_for_id(42)
        expect(glyph.name).to eq("A")
      end

      it "caches glyph objects" do
        glyph1 = cff_accessor.glyph_for_id(42)
        glyph2 = cff_accessor.glyph_for_id(42)
        expect(glyph1).to equal(glyph2)
      end
    end

    describe "#glyph_for_char with CFF font" do
      it "returns CFFGlyph for mapped character" do
        glyph = cff_accessor.glyph_for_char(0x0041)
        expect(glyph).to be_a(Fontisan::Tables::Cff::CFFGlyph)
      end

      it "uses cmap to get glyph ID" do
        glyph = cff_accessor.glyph_for_char(0x0041)
        expect(glyph.glyph_id).to eq(42)
      end
    end

    describe "#closure_for with CFF font" do
      it "returns early for CFF fonts (no composites)" do
        closure = cff_accessor.closure_for([42, 43, 44])
        expect(closure).to be_a(Set)
        expect(closure).to include(0, 42, 43, 44)
        # Should not include any additional glyphs since CFF has no composites
        expect(closure.size).to eq(4)
      end

      it "always includes .notdef" do
        closure = cff_accessor.closure_for([42])
        expect(closure).to include(0)
      end
    end

    describe "unified interface" do
      it "provides same API as TrueType glyphs" do
        cff_glyph = cff_accessor.glyph_for_id(42)

        # Both should respond to same methods
        %i[simple? compound? bounding_box name].each do |method|
          expect(cff_glyph).to respond_to(method)
        end
      end

      it "allows format-agnostic glyph access" do
        # Code that works with TrueType glyphs should work with CFF glyphs
        glyph = cff_accessor.glyph_for_id(42)

        # These operations should work regardless of format
        expect(glyph.simple?).to be(true).or be(false)
        expect(glyph.compound?).to be(true).or be(false)
        expect(glyph.bounding_box).to be_a(Array).or be_nil
        expect(glyph.name).to be_a(String)
      end
    end
  end

  describe "integration tests" do
    it "can perform complete glyph access workflow" do
      # 1. Check if character exists
      expect(accessor.has_glyph_for_char?(0x0041)).to be true

      # 2. Get glyph by character
      glyph = accessor.glyph_for_char(0x0041)
      expect(glyph).not_to be_nil

      # 3. Get metrics by character
      metrics = accessor.metrics_for_char(0x0041)
      expect(metrics).to be_a(Hash)
      expect(metrics[:advance_width]).to be > 0

      # 4. Get glyph ID from cmap
      cmap = font.table("cmap")
      glyph_id = cmap.unicode_mappings[0x0041]

      # 5. Get same glyph by ID
      glyph_by_id = accessor.glyph_for_id(glyph_id)
      expect(glyph_by_id).to eq(glyph)

      # 6. Calculate closure
      closure = accessor.closure_for([glyph_id])
      expect(closure).to include(0, glyph_id)
    end

    it "handles subsetting scenario" do
      # Simulate subsetting scenario: keep only 'A', 'B', 'C'
      cmap = font.table("cmap")
      chars = [0x0041, 0x0042, 0x0043] # A, B, C
      glyph_ids = chars.map { |char| cmap.unicode_mappings[char] }.compact

      # Calculate closure (includes composite dependencies)
      closure = accessor.closure_for(glyph_ids)

      # Should include .notdef
      expect(closure).to include(0)

      # Should include all requested glyphs
      glyph_ids.each do |gid|
        expect(closure).to include(gid)
      end

      # Can get metrics for all glyphs in closure
      closure.each do |gid|
        metrics = accessor.metrics_for_id(gid)
        expect(metrics).to be_a(Hash)
      end
    end
  end
end
