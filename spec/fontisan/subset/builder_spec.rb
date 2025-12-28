# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Subset::Builder do
  let(:font_path) { fixture_path("fonts/noto-sans/NotoSans-Regular.ttf") }
  let(:font) { Fontisan::TrueTypeFont.from_file(font_path) }
  let(:glyph_ids) { [0, 1, 65, 66, 67] } # .notdef, NULL, A, B, C
  let(:options) { Fontisan::Subset::Options.new(profile: "pdf") }
  let(:builder) { described_class.new(font, glyph_ids, options) }

  describe "#initialize" do
    it "initializes with font, glyph_ids, and options" do
      expect(builder.font).to eq(font)
      expect(builder.glyph_ids).to eq(glyph_ids)
      expect(builder.options).to be_a(Fontisan::Subset::Options)
    end

    it "accepts options as a hash" do
      builder_with_hash = described_class.new(font, glyph_ids, profile: "web")
      expect(builder_with_hash.options).to be_a(Fontisan::Subset::Options)
      expect(builder_with_hash.options.profile).to eq("web")
    end

    it "initializes closure and mapping as nil" do
      expect(builder.closure).to be_nil
      expect(builder.mapping).to be_nil
    end
  end

  describe "#build" do
    it "returns a binary string" do
      result = builder.build
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "produces a non-empty font binary" do
      result = builder.build
      expect(result.bytesize).to be > 100
    end

    it "includes required table directory structure" do
      result = builder.build

      # Check sfnt version (first 4 bytes)
      sfnt_version = result[0, 4].unpack1("N")
      expect([0x00010000, 0x4F54544F]).to include(sfnt_version)

      # Check numTables (offset 4, uint16)
      num_tables = result[4, 2].unpack1("n")
      expect(num_tables).to be > 0
    end

    it "sets closure and mapping after build" do
      builder.build
      expect(builder.closure).to be_a(Set)
      expect(builder.mapping).to be_a(Fontisan::Subset::GlyphMapping)
    end

    it "always includes .notdef glyph (ID 0)" do
      builder.build
      expect(builder.closure).to include(0)
      expect(builder.mapping.include?(0)).to be true
    end
  end

  describe "validation" do
    describe "#validate_input!" do
      it "raises error for nil font" do
        expect do
          described_class.new(nil, glyph_ids, options).build
        end.to raise_error(ArgumentError, /Font cannot be nil/)
      end

      it "raises error for font without table method" do
        invalid_font = double("InvalidFont")
        expect do
          described_class.new(invalid_font, glyph_ids, options).build
        end.to raise_error(ArgumentError, /must respond to :table/)
      end

      it "raises error for empty glyph_ids" do
        expect do
          described_class.new(font, [], options).build
        end.to raise_error(ArgumentError, /At least one glyph ID/)
      end

      it "raises error for invalid profile" do
        invalid_options = Fontisan::Subset::Options.new(profile: "invalid")
        expect do
          described_class.new(font, glyph_ids, invalid_options).build
        end.to raise_error(ArgumentError, /Invalid profile/)
      end

      it "raises error for out of range glyph IDs" do
        maxp = font.table("maxp")
        invalid_id = maxp.num_glyphs + 100

        expect do
          described_class.new(font, [invalid_id], options).build
        end.to raise_error(ArgumentError, /exceeds font's glyph count/)
      end

      it "raises error for negative glyph IDs" do
        expect do
          described_class.new(font, [-1], options).build
        end.to raise_error(ArgumentError, /Invalid glyph ID/)
      end
    end
  end

  describe "closure calculation" do
    it "calculates closure including composite dependencies" do
      # Use glyphs that might have composite dependencies
      builder.build

      # Closure should include at least the requested glyphs plus .notdef
      expect(builder.closure.size).to be >= glyph_ids.size
      glyph_ids.each do |gid|
        expect(builder.closure).to include(gid)
      end
    end

    it "includes .notdef when include_notdef option is true" do
      opts = Fontisan::Subset::Options.new(include_notdef: true)
      builder_with_notdef = described_class.new(font, [65], opts)
      builder_with_notdef.build

      expect(builder_with_notdef.closure).to include(0)
    end

    it "handles fonts with composite glyphs" do
      # This will test if composite glyph dependencies are tracked
      builder.build

      # Should complete without error
      expect(builder.closure).to be_a(Set)
      expect(builder.closure.size).to be > 0
    end
  end

  describe "glyph mapping" do
    context "with compact mode (retain_gids: false)" do
      let(:options) { Fontisan::Subset::Options.new(retain_gids: false) }

      it "creates sequential mapping" do
        builder.build

        # Mapping should be sequential starting from 0
        expect(builder.mapping.new_id(0)).to eq(0)

        # All new IDs should be sequential
        new_ids = builder.closure.map do |old_id|
          builder.mapping.new_id(old_id)
        end
        expect(new_ids).to eq(new_ids.sort)
      end

      it "produces compact glyph count" do
        builder.build
        expect(builder.mapping.size).to eq(builder.closure.size)
      end
    end

    context "with retain_gids mode" do
      let(:options) { Fontisan::Subset::Options.new(retain_gids: true) }

      it "preserves original glyph IDs" do
        builder.build

        builder.closure.each do |old_id|
          expect(builder.mapping.new_id(old_id)).to eq(old_id)
        end
      end

      it "produces glyph count up to max ID" do
        builder.build
        max_id = builder.closure.max
        expect(builder.mapping.size).to eq(max_id + 1)
      end
    end
  end

  describe "table subsetting" do
    it "includes all tables from the profile" do
      result = builder.build

      # Parse table directory
      num_tables = result[4, 2].unpack1("n")

      # Read table tags
      table_tags = []
      offset = 12 # After offset table
      num_tables.times do
        tag = result[offset, 4]
        table_tags << tag
        offset += 16 # Each entry is 16 bytes
      end

      # Should include core PDF tables
      expect(table_tags).to include("head")
      expect(table_tags).to include("maxp")
      expect(table_tags).to include("hhea")
    end

    it "handles fonts without optional tables" do
      # Should complete successfully even if optional tables are missing
      result = builder.build
      expect(result.bytesize).to be > 0
    end
  end

  describe "different profiles" do
    it "subsets with pdf profile" do
      pdf_builder = described_class.new(font, glyph_ids,
                                        Fontisan::Subset::Options.new(profile: "pdf"))
      result = pdf_builder.build
      expect(result.bytesize).to be > 0
    end

    it "subsets with web profile" do
      web_builder = described_class.new(font, glyph_ids,
                                        Fontisan::Subset::Options.new(profile: "web"))
      result = web_builder.build
      expect(result.bytesize).to be > 0
    end

    it "subsets with minimal profile" do
      minimal_builder = described_class.new(font, glyph_ids,
                                            Fontisan::Subset::Options.new(profile: "minimal"))
      result = minimal_builder.build
      expect(result.bytesize).to be > 0
    end
  end

  describe "subsetting options" do
    it "handles drop_hints option" do
      opts = Fontisan::Subset::Options.new(drop_hints: true)
      builder_with_opts = described_class.new(font, glyph_ids, opts)
      result = builder_with_opts.build
      expect(result.bytesize).to be > 0
    end

    it "handles drop_names option" do
      opts = Fontisan::Subset::Options.new(drop_names: true)
      builder_with_opts = described_class.new(font, glyph_ids, opts)
      result = builder_with_opts.build
      expect(result.bytesize).to be > 0
    end

    it "handles combined options" do
      opts = Fontisan::Subset::Options.new(
        drop_hints: true,
        drop_names: true,
        retain_gids: false,
      )
      builder_with_opts = described_class.new(font, glyph_ids, opts)
      result = builder_with_opts.build
      expect(result.bytesize).to be > 0
    end
  end

  describe "font assembly" do
    it "determines correct sfnt version for TrueType fonts" do
      result = builder.build
      sfnt_version = result[0, 4].unpack1("N")

      # TrueType fonts should have version 0x00010000
      expect(sfnt_version).to eq(0x00010000)
    end

    it "produces valid table directory structure" do
      result = builder.build

      # Validate offset table
      num_tables = result[4, 2].unpack1("n")
      search_range = result[6, 2].unpack1("n")
      result[8, 2].unpack1("n")
      range_shift = result[10, 2].unpack1("n")

      # Validate search parameters
      expect(search_range % 16).to eq(0)
      expect(range_shift).to eq((num_tables * 16) - search_range)
    end
  end

  describe "error handling" do
    it "raises SubsettingError for table subsetting failures" do
      # Create a builder with mocked font that will cause errors
      bad_font = font
      # Allow all table calls to work normally except maxp
      allow(bad_font).to receive(:table).and_call_original
      allow(bad_font).to receive(:table).with("maxp").and_return(nil)

      expect do
        described_class.new(bad_font, glyph_ids, options).build
      end.to raise_error(Fontisan::MissingTableError)
    end

    it "provides informative error messages" do
      expect do
        described_class.new(font, [99999], options).build
      end.to raise_error(ArgumentError, /exceeds/)
    end
  end

  describe "edge cases" do
    it "handles subsetting to single glyph" do
      single_builder = described_class.new(font, [0], options)
      result = single_builder.build
      expect(result.bytesize).to be > 0
    end

    it "handles large glyph sets" do
      # Subset to first 100 glyphs
      large_ids = (0...100).to_a
      large_builder = described_class.new(font, large_ids, options)
      result = large_builder.build
      expect(result.bytesize).to be > 0
    end

    it "handles duplicate glyph IDs in input" do
      duplicate_ids = [0, 0, 65, 65, 66]
      dup_builder = described_class.new(font, duplicate_ids, options)
      result = dup_builder.build

      # Should handle duplicates gracefully
      expect(result.bytesize).to be > 0
      expect(dup_builder.closure.size).to be < duplicate_ids.size
    end
  end

  describe "integration with other components" do
    it "uses GlyphAccessor for closure calculation" do
      accessor_double = instance_double(Fontisan::GlyphAccessor)
      allow(Fontisan::GlyphAccessor).to receive(:new).and_return(accessor_double)
      allow(accessor_double).to receive(:closure_for).and_return(Set.new([0,
                                                                          65]))

      builder.build
      expect(Fontisan::GlyphAccessor).to have_received(:new).with(font)
    end

    it "uses TableSubsetter for table operations" do
      subsetter_class = class_double(Fontisan::Subset::TableSubsetter).as_stubbed_const
      subsetter_instance = instance_double(Fontisan::Subset::TableSubsetter)

      allow(subsetter_class).to receive(:new).and_return(subsetter_instance)
      allow(subsetter_instance).to receive(:subset_table).and_return("test")

      builder.build
      expect(subsetter_class).to have_received(:new)
    end

    it "uses FontWriter for font assembly" do
      expect(Fontisan::FontWriter).to receive(:write_font).and_call_original
      builder.build
    end
  end
end
