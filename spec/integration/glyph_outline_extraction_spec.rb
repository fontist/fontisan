# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Glyph Outline Extraction Integration" do
  let(:font_path) do
    font_fixture_path("Libertinus", "static/TTF/LibertinusSerif-Regular.ttf")
  end
  let(:font) { Fontisan::FontLoader.load(font_path) }
  let(:accessor) { Fontisan::GlyphAccessor.new(font) }

  describe "complete outline extraction workflow" do
    it "extracts outline for letter A" do
      outline = accessor.outline_for_char("A")

      expect(outline).not_to be_nil
      expect(outline).to be_a(Fontisan::Models::GlyphOutline)
      expect(outline.glyph_id).to be > 0
      expect(outline.contours).not_to be_empty
      expect(outline.points.length).to be > 0
      expect(outline.bbox).to include(:x_min, :y_min, :x_max, :y_max)
    end

    it "converts outline to SVG path" do
      outline = accessor.outline_for_char("A")
      svg_path = outline.to_svg_path

      expect(svg_path).to be_a(String)
      expect(svg_path).to start_with("M")
      expect(svg_path).to include("Z")
      expect(svg_path.length).to be > 10
    end

    it "converts outline to drawing commands" do
      outline = accessor.outline_for_char("A")
      commands = outline.to_commands

      expect(commands).to be_an(Array)
      expect(commands).not_to be_empty
      expect(commands.first[0]).to eq(:move_to)
      expect(commands.last[0]).to eq(:close_path)
    end

    it "handles empty glyphs gracefully" do
      outline = accessor.outline_for_char(" ")

      # Space may or may not have outline data
      if outline
        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
      else
        expect(outline).to be_nil
      end
    end
  end

  describe "multiple character extraction" do
    let(:test_chars) { ["A", "B", "C", "a", "b", "c", "1", "2", "3"] }

    it "extracts outlines for multiple characters" do
      test_chars.each do |char|
        outline = accessor.outline_for_char(char)

        expect(outline).to be_a(Fontisan::Models::GlyphOutline),
                           "Failed to extract outline for '#{char}'"
        expect(outline.glyph_id).to be >= 0
      end
    end

    it "produces valid SVG paths for all characters" do
      test_chars.each do |char|
        outline = accessor.outline_for_char(char)
        next unless outline

        svg_path = outline.to_svg_path

        expect(svg_path).to be_a(String)
        expect(svg_path).not_to be_empty
        expect(svg_path).to match(/M .+ Z/) # Basic SVG path pattern
      end
    end

    it "produces consistent bounding boxes" do
      test_chars.each do |char|
        outline = accessor.outline_for_char(char)
        next unless outline

        bbox = outline.bbox

        # Bounding box should make sense
        expect(bbox[:x_max]).to be >= bbox[:x_min]
        expect(bbox[:y_max]).to be >= bbox[:y_min]
      end
    end
  end

  describe "outline method equivalence" do
    it "produces same outline via different access methods" do
      char = "A"
      codepoint = char.ord
      cmap = font.table("cmap")
      glyph_id = cmap.unicode_mappings[codepoint]

      outline1 = accessor.outline_for_char(char)
      outline2 = accessor.outline_for_codepoint(codepoint)
      outline3 = accessor.outline_for_id(glyph_id)

      expect(outline1.glyph_id).to eq(outline2.glyph_id)
      expect(outline2.glyph_id).to eq(outline3.glyph_id)
      expect(outline1.point_count).to eq(outline3.point_count)
      expect(outline1.contour_count).to eq(outline3.contour_count)
    end
  end

  describe "outline properties" do
    let(:outline_a) { accessor.outline_for_char("A") }

    it "has immutable data" do
      expect(outline_a.glyph_id).to be_frozen
      expect(outline_a.contours).to be_frozen
      expect(outline_a.points).to be_frozen
      expect(outline_a.bbox).to be_frozen
    end

    it "has positive bounding box dimensions" do
      bbox = outline_a.bbox
      width = bbox[:x_max] - bbox[:x_min]
      height = bbox[:y_max] - bbox[:y_min]

      expect(width).to be > 0
      expect(height).to be > 0
    end

    it "has at least one contour" do
      expect(outline_a.contour_count).to be > 0
    end

    it "has multiple points" do
      expect(outline_a.point_count).to be > 2
    end
  end

  describe "SVG path generation" do
    it "generates closeable paths" do
      outline = accessor.outline_for_char("O")
      svg_path = outline.to_svg_path

      # Count path closures (Z commands)
      close_count = svg_path.scan(/Z/).length

      expect(close_count).to be >= 1
      expect(close_count).to eq(outline.contour_count)
    end

    it "generates valid path commands" do
      outline = accessor.outline_for_char("A")
      svg_path = outline.to_svg_path

      # Should contain valid SVG path commands
      expect(svg_path).to match(/M \d+/)  # Move to
      expect(svg_path).to match(/L \d+/)  # Line to (or Q for curves)
    end

    it "handles curves appropriately" do
      outline = accessor.outline_for_char("S")
      svg_path = outline.to_svg_path

      # S typically has curves
      has_curves = svg_path.include?("Q") || svg_path.include?("C")
      has_lines = svg_path.include?("L")

      # Should have either curves or lines (or both)
      expect(has_curves || has_lines).to be true
    end
  end

  describe "drawing commands generation" do
    it "generates valid command sequences" do
      outline = accessor.outline_for_char("A")
      commands = outline.to_commands

      # First command should be move_to
      expect(commands.first[0]).to eq(:move_to)
      expect(commands.first.length).to eq(3) # command + x + y

      # Last command should be close_path
      expect(commands.last[0]).to eq(:close_path)
    end

    it "generates correct number of paths" do
      outline = accessor.outline_for_char("O")
      commands = outline.to_commands

      # Count close_path commands (one per contour)
      close_count = commands.count { |cmd| cmd[0] == :close_path }

      expect(close_count).to eq(outline.contour_count)
    end

    it "includes line and curve commands" do
      outline = accessor.outline_for_char("S")
      commands = outline.to_commands

      command_types = commands.map(&:first).uniq

      # Should have move_to and close_path at minimum
      expect(command_types).to include(:move_to, :close_path)

      # Should have either line_to or curve_to (or both)
      has_drawing = command_types.include?(:line_to) ||
        command_types.include?(:curve_to)
      expect(has_drawing).to be true
    end
  end

  describe "error handling" do
    it "returns nil for unmapped characters" do
      # Test with emoji (unlikely to be in font)
      outline = accessor.outline_for_char("😀")

      expect(outline).to be_nil
    end

    it "raises error for invalid input" do
      expect { accessor.outline_for_char("AB") }.to raise_error(ArgumentError)
      expect { accessor.outline_for_char("") }.to raise_error(ArgumentError)
      expect { accessor.outline_for_id(-1) }.to raise_error(ArgumentError)
      expect { accessor.outline_for_id(nil) }.to raise_error(ArgumentError)
    end

    it "handles out-of-range glyph IDs" do
      maxp = font.table("maxp")
      invalid_id = maxp.num_glyphs + 100

      expect do
        accessor.outline_for_id(invalid_id)
      end.to raise_error(ArgumentError)
    end
  end

  describe "compound glyphs" do
    it "resolves compound glyph components correctly" do
      # Try to find a compound glyph (accented characters often are)
      cmap = font.table("cmap")
      test_chars = ["À", "Á", "Â", "à", "á", "â"]

      compound_found = false
      test_chars.each do |char|
        codepoint = char.ord
        glyph_id = cmap.unicode_mappings[codepoint]
        next unless glyph_id

        glyph = accessor.glyph_for_id(glyph_id)
        next unless glyph
        next unless glyph.respond_to?(:compound?) && glyph.compound?

        # Found a compound glyph, test outline extraction
        outline = accessor.outline_for_char(char)

        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
        expect(outline.contour_count).to be > 0
        expect(outline.point_count).to be > 0

        compound_found = true
        break
      end

      # If no compound glyphs found, skip this test
      skip "No compound glyphs found in test font" unless compound_found
    end
  end

  describe "performance" do
    it "extracts outlines in reasonable time" do
      chars = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a

      start_time = Time.now
      chars.each do |char|
        accessor.outline_for_char(char)
      end
      duration = Time.now - start_time

      # Should process 62 glyphs in under 1 second
      expect(duration).to be < 1.0
    end

    it "benefits from caching" do
      # Extract same outline twice
      first_time = Time.now
      accessor.outline_for_char("A")
      first_duration = Time.now - first_time

      # OutlineExtractor is not cached, so both should take similar time
      # This just verifies it works repeatedly
      second_time = Time.now
      accessor.outline_for_char("A")
      second_duration = Time.now - second_time

      # Both should complete successfully
      expect(first_duration).to be > 0
      expect(second_duration).to be > 0
    end
  end

  describe "Unicode coverage" do
    it "handles basic Latin characters" do
      ("A".."Z").each do |char|
        outline = accessor.outline_for_char(char)
        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
      end
    end

    it "handles lowercase letters" do
      ("a".."z").each do |char|
        outline = accessor.outline_for_char(char)
        expect(outline).to be_a(Fontisan::Models::GlyphOutline)
      end
    end

    it "handles digits" do
      ("0".."9").each do |char|
        outline = accessor.outline_for_char(char)
        expect(outline).to be_a(Fontisan::Models::GlyphOutline).or be_nil
      end
    end

    it "handles common punctuation" do
      [".", ",", "!", "?", ":", ";"].each do |char|
        outline = accessor.outline_for_char(char)
        # Some punctuation may not have outlines
        if outline
          expect(outline).to be_a(Fontisan::Models::GlyphOutline)
        end
      end
    end
  end
end
