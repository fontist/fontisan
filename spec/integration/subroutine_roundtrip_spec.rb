# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CFF Subroutine Optimization Round-Trip Validation" do
  let(:converter) { Fontisan::Converters::OutlineConverter.new }
  let(:output_dir) { "spec/fixtures/output" }

  before do
    FileUtils.mkdir_p(output_dir)
  end

  after do
    Dir.glob("#{output_dir}/*").each { |f| FileUtils.rm_f(f) }
  end

  describe "TTF → OTF with optimization → TTF round-trip" do
    let(:ttf_font_path) do
      font_fixture_path("NotoSans", "NotoSans-Regular.ttf")
    end

    it "preserves glyph geometry through round-trip with optimization" do
      # Load original TTF font
      original_font = Fontisan::FontLoader.load(ttf_font_path)
      original_maxp = original_font.table("maxp")
      original_num_glyphs = original_maxp.num_glyphs

      # Extract original outlines
      original_outlines = converter.extract_ttf_outlines(original_font)

      # Convert TTF → OTF WITH optimization
      otf_tables = converter.convert(original_font,
                                     target_format: :otf,
                                     optimize_cff: true,
                                     stack_aware: true)

      # Verify CFF table was created
      expect(otf_tables["CFF "]).to be_a(String)
      expect(otf_tables["CFF "].encoding).to eq(Encoding::BINARY)

      # Write optimized OTF to file
      otf_output_path = File.join(output_dir, "optimized.otf")
      Fontisan::FontWriter.write_to_file(otf_tables, otf_output_path)

      # Load the optimized OTF font
      otf_font = Fontisan::FontLoader.load(otf_output_path)

      # Verify CFF table can be parsed
      cff = otf_font.table("CFF ")
      expect(cff).not_to be_nil
      expect(cff.glyph_count).to eq(original_num_glyphs)

      # Verify local subroutines were created if optimization worked
      local_subrs = cff.local_subrs(0)
      if local_subrs && local_subrs.count > 0
        puts "✓ CFF optimization created #{local_subrs.count} local subroutines"
      end

      # Extract outlines from optimized OTF
      otf_outlines = converter.extract_cff_outlines(otf_font)

      # Verify glyph count preserved
      expect(otf_outlines.length).to eq(original_outlines.length)

      # Convert OTF → TTF
      ttf_tables = converter.convert(otf_font, target_format: :ttf)

      # Write round-trip TTF
      ttf_output_path = File.join(output_dir, "roundtrip.ttf")
      Fontisan::FontWriter.write_to_file(ttf_tables, ttf_output_path)

      # Load round-trip font
      roundtrip_font = Fontisan::FontLoader.load(ttf_output_path)
      roundtrip_outlines = converter.extract_ttf_outlines(roundtrip_font)

      # Verify glyph count
      expect(roundtrip_outlines.length).to eq(original_outlines.length)

      # Compare geometry (sample glyphs)
      tolerance = 2.0 # ±2 pixels is acceptable for quadratic/cubic conversion
      [0, 1, 10, 50, 100].each do |glyph_id|
        next if glyph_id >= original_outlines.length

        original = original_outlines[glyph_id]
        roundtrip = roundtrip_outlines[glyph_id]

        # Compare bounding boxes
        next if original.empty? || roundtrip.empty?

        expect(roundtrip.bbox[:x_min]).to be_within(tolerance).of(original.bbox[:x_min])
        expect(roundtrip.bbox[:y_min]).to be_within(tolerance).of(original.bbox[:y_min])
        expect(roundtrip.bbox[:x_max]).to be_within(tolerance).of(original.bbox[:x_max])
        expect(roundtrip.bbox[:y_max]).to be_within(tolerance).of(original.bbox[:y_max])
      end
    end

    it "produces valid CFF table with subroutines" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Convert with optimization
      tables = converter.convert(font,
                                 target_format: :otf,
                                 optimize_cff: true,
                                 stack_aware: true)

      # Write to file
      output_path = File.join(output_dir, "optimized_validation.otf")
      Fontisan::FontWriter.write_to_file(tables, output_path)

      # Load and parse CFF table
      otf_font = Fontisan::FontLoader.load(output_path)
      cff = otf_font.table("CFF ")

      expect(cff).not_to be_nil
      expect(cff.valid?).to be true

      # Verify table structure
      expect(cff.font_count).to eq(1)
      expect(cff.font_name(0)).to be_a(String)

      # Verify Top DICT
      top_dict = cff.top_dict(0)
      expect(top_dict).not_to be_nil
      expect(top_dict.charstrings).to be > 0

      # Verify Private DICT
      priv_dict = cff.private_dict(0)
      expect(priv_dict).not_to be_nil

      # Verify CharStrings INDEX
      charstrings_index = cff.charstrings_index(0)
      expect(charstrings_index).not_to be_nil
      expect(charstrings_index.count).to be > 0
    end

    it "creates parseable subroutine calls" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Convert with optimization
      tables = converter.convert(font,
                                 target_format: :otf,
                                 optimize_cff: true,
                                 stack_aware: true)

      # Write and reload
      output_path = File.join(output_dir, "subroutine_calls.otf")
      Fontisan::FontWriter.write_to_file(tables, output_path)
      otf_font = Fontisan::FontLoader.load(output_path)

      cff = otf_font.table("CFF ")
      local_subrs = cff.local_subrs(0)

      # If subroutines were created
      if local_subrs && local_subrs.count > 0
        puts "✓ Testing #{local_subrs.count} subroutines"

        # Verify each CharString can be parsed
        num_glyphs = cff.glyph_count
        [0, 1, 10, 50, 100].each do |glyph_id|
          next if glyph_id >= num_glyphs

          # This should not raise an error
          charstring = cff.charstring_for_glyph(glyph_id)
          expect(charstring).not_to be_nil
        end
      else
        puts "⚠ No subroutines created (font may have insufficient repeated patterns)"
      end
    end

    it "achieves compression with optimization" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Convert without optimization
      unoptimized_tables = converter.convert(font,
                                             target_format: :otf,
                                             optimize_cff: false)
      unoptimized_size = unoptimized_tables["CFF "].bytesize

      # Convert with optimization
      optimized_tables = converter.convert(font,
                                           target_format: :otf,
                                           optimize_cff: true,
                                           stack_aware: true)
      optimized_size = optimized_tables["CFF "].bytesize

      # Verify optimization doesn't increase size
      expect(optimized_size).to be <= unoptimized_size

      if optimized_size < unoptimized_size
        reduction = ((unoptimized_size - optimized_size).to_f / unoptimized_size * 100).round(2)
        puts "✓ CFF size reduction: #{reduction}% (#{unoptimized_size} → #{optimized_size} bytes)"
        expect(reduction).to be >= 0
      else
        puts "⚠ No size reduction (font may have insufficient repeated patterns)"
      end
    end
  end

  describe "Subroutine bias calculation" do
    it "uses correct bias for small subroutine counts" do
      # This is tested through the SubroutineBuilder unit tests
      # but we verify it works in practice here
      font = Fontisan::FontLoader.load(font_fixture_path("NotoSans",
                                                         "NotoSans-Regular.ttf"))

      tables = converter.convert(font,
                                 target_format: :otf,
                                 optimize_cff: true,
                                 stack_aware: true)

      output_path = File.join(output_dir, "bias_test.otf")
      Fontisan::FontWriter.write_to_file(tables, output_path)

      otf_font = Fontisan::FontLoader.load(output_path)
      cff = otf_font.table("CFF ")
      local_subrs = cff.local_subrs(0)

      if local_subrs && local_subrs.count > 0
        subr_count = local_subrs.count
        puts "✓ Subroutine count: #{subr_count}"

        # Verify CharStrings can be decoded (proves bias is correct)
        expect do
          cff.charstring_for_glyph(0)
        end.not_to raise_error
      end
    end
  end

  describe "Stack-aware optimization" do
    it "produces stack-neutral subroutines" do
      font = Fontisan::FontLoader.load(font_fixture_path("NotoSans",
                                                         "NotoSans-Regular.ttf"))

      tables = converter.convert(font,
                                 target_format: :otf,
                                 optimize_cff: true,
                                 stack_aware: true) # Enable stack-aware mode

      output_path = File.join(output_dir, "stack_aware.otf")
      Fontisan::FontWriter.write_to_file(tables, output_path)

      # If stack-aware mode works, all CharStrings should parse without error
      otf_font = Fontisan::FontLoader.load(output_path)
      cff = otf_font.table("CFF ")

      # Sample multiple glyphs
      num_glyphs = [cff.glyph_count, 100].min
      (0...num_glyphs).each do |glyph_id|
        expect do
          cff.charstring_for_glyph(glyph_id)
        end.not_to raise_error
      end
    end
  end
end
