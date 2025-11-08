# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Post do
  # Helper to build valid post table binary data
  def build_post_table(
    version: 1.0,
    italic_angle: 0.0,
    underline_position: -100,
    underline_thickness: 50,
    is_fixed_pitch: 0,
    min_mem_type42: 0,
    max_mem_type42: 0,
    min_mem_type1: 0,
    max_mem_type1: 0,
    num_glyphs: nil,
    indices: nil,
    custom_names: nil
  )
    data = (+"").b

    # Version (Fixed 16.16)
    # Pack as 32-bit signed big-endian
    version_fixed = (version * 65_536).to_i
    data << [version_fixed].pack("N")

    # Italic Angle (Fixed 16.16)
    # Pack as 32-bit signed big-endian
    italic_angle_fixed = (italic_angle * 65_536).to_i
    data << [italic_angle_fixed].pack("N")

    # Underline Position (FWord -  int16)
    # For signed 16-bit, convert negative to unsigned representation
    underline_pos_packed = underline_position < 0 ? (underline_position + 65_536) : underline_position
    data << [underline_pos_packed].pack("n")

    # Underline Thickness (FWord - int16)
    underline_thick_packed = underline_thickness < 0 ? (underline_thickness + 65_536) : underline_thickness
    data << [underline_thick_packed].pack("n")

    # isFixedPitch (uint32)
    data << [is_fixed_pitch].pack("N")

    # minMemType42 (uint32)
    data << [min_mem_type42].pack("N")

    # maxMemType42 (uint32)
    data << [max_mem_type42].pack("N")

    # minMemType1 (uint32)
    data << [min_mem_type1].pack("N")

    # maxMemType1 (uint32)
    data << [max_mem_type1].pack("N")

    # Version-specific data
    # rubocop:disable Lint/FloatComparison
    if version == 2.0
      # Number of glyphs (uint16)
      data << [num_glyphs || 0].pack("n")

      # Glyph name indices (array of uint16)
      indices&.each do |index|
        data << [index].pack("n")
      end

      # Pascal strings for custom names
      custom_names&.each do |name|
        data << [name.length].pack("C") # uint8 length
        data << name.b # string
      end
    end
    # rubocop:enable Lint/FloatComparison

    data
  end

  describe "version 1.0" do
    let(:data) { build_post_table(version: 1.0) }
    let(:post) { described_class.read(data) }

    it "uses standard Mac glyph names" do
      expect(post.glyph_names).to eq(described_class::STANDARD_NAMES)
    end

    it "has 258 standard names" do
      expect(post.glyph_names.length).to eq(258)
    end

    it "includes .notdef as first name" do
      expect(post.glyph_names[0]).to eq(".notdef")
    end

    it "includes standard ASCII names" do
      expect(post.glyph_names).to include("A", "B", "C", "a", "b", "c")
      expect(post.glyph_names).to include("zero", "one", "two")
      expect(post.glyph_names).to include("space", "exclam", "at")
    end

    it "includes special character names" do
      expect(post.glyph_names).to include("Adieresis", "Aring", "Ccedilla")
      expect(post.glyph_names).to include("copyright", "trademark",
                                          "registered")
    end

    it "parses version correctly" do
      expect(post.version).to be_within(0.001).of(1.0)
    end
  end

  describe "version 2.0" do
    context "with only standard names" do
      let(:indices) { [0, 1, 36, 68] } # .notdef, .null, A, a
      let(:data) do
        build_post_table(
          version: 2.0,
          num_glyphs: indices.length,
          indices: indices,
          custom_names: [],
        )
      end
      let(:post) { described_class.read(data) }

      it "parses custom glyph names" do
        expect(post.glyph_names.length).to eq(4)
      end

      it "maps indices correctly" do
        expect(post.glyph_names[0]).to eq(".notdef")
        expect(post.glyph_names[1]).to eq(".null")
        expect(post.glyph_names[2]).to eq("A")
        expect(post.glyph_names[3]).to eq("a")
      end
    end

    context "with custom names" do
      let(:indices) { [0, 258, 259, 36] } # .notdef, custom1, custom2, A
      let(:custom_names) { %w[customGlyph1 customGlyph2] }
      let(:data) do
        build_post_table(
          version: 2.0,
          num_glyphs: indices.length,
          indices: indices,
          custom_names: custom_names,
        )
      end
      let(:post) { described_class.read(data) }

      it "combines standard and custom names" do
        expect(post.glyph_names.length).to eq(4)
        expect(post.glyph_names[0]).to eq(".notdef")
        expect(post.glyph_names[1]).to eq("customGlyph1")
        expect(post.glyph_names[2]).to eq("customGlyph2")
        expect(post.glyph_names[3]).to eq("A")
      end

      it "handles Pascal string parsing" do
        expect(post.glyph_names[1]).to eq("customGlyph1")
        expect(post.glyph_names[2]).to eq("customGlyph2")
      end
    end

    context "with mixed indices" do
      let(:indices) { [0, 100, 258, 259, 50] }
      let(:custom_names) { %w[special extra] }
      let(:data) do
        build_post_table(
          version: 2.0,
          num_glyphs: indices.length,
          indices: indices,
          custom_names: custom_names,
        )
      end
      let(:post) { described_class.read(data) }

      it "correctly maps both standard and custom names" do
        expect(post.glyph_names[0]).to eq(".notdef")
        expect(post.glyph_names[1]).to eq(described_class::STANDARD_NAMES[100])
        expect(post.glyph_names[2]).to eq("special")
        expect(post.glyph_names[3]).to eq("extra")
        expect(post.glyph_names[4]).to eq(described_class::STANDARD_NAMES[50])
      end
    end

    context "with missing custom names" do
      let(:indices) { [0, 258, 259, 260] } # References 3 custom names
      let(:custom_names) { ["custom1"] } # Only 1 provided
      let(:data) do
        build_post_table(
          version: 2.0,
          num_glyphs: indices.length,
          indices: indices,
          custom_names: custom_names,
        )
      end
      let(:post) { described_class.read(data) }

      it "uses .notdef for missing custom names" do
        expect(post.glyph_names[0]).to eq(".notdef")
        expect(post.glyph_names[1]).to eq("custom1")
        expect(post.glyph_names[2]).to eq(".notdef")
        expect(post.glyph_names[3]).to eq(".notdef")
      end
    end

    it "parses version correctly" do
      data = build_post_table(version: 2.0, num_glyphs: 0)
      post = described_class.read(data)
      expect(post.version).to be_within(0.001).of(2.0)
    end
  end

  describe "version 2.5" do
    let(:data) { build_post_table(version: 2.5) }
    let(:post) { described_class.read(data) }

    it "returns empty glyph names array" do
      expect(post.glyph_names).to eq([])
    end

    it "parses version correctly" do
      expect(post.version).to be_within(0.001).of(2.5)
    end
  end

  describe "version 3.0" do
    let(:data) { build_post_table(version: 3.0) }
    let(:post) { described_class.read(data) }

    it "returns empty glyph names array" do
      expect(post.glyph_names).to eq([])
    end

    it "parses version correctly" do
      expect(post.version).to be_within(0.001).of(3.0)
    end
  end

  describe "version 4.0" do
    let(:data) { build_post_table(version: 4.0) }
    let(:post) { described_class.read(data) }

    it "returns empty glyph names array" do
      expect(post.glyph_names).to eq([])
    end

    it "parses version correctly" do
      expect(post.version).to be_within(0.001).of(4.0)
    end
  end

  describe "common fields" do
    context "with default values" do
      let(:data) { build_post_table }
      let(:post) { described_class.read(data) }

      it "parses italic angle" do
        expect(post.italic_angle).to be_within(0.001).of(0.0)
      end

      it "parses underline position" do
        expect(post.underline_position).to eq(-100)
      end

      it "parses underline thickness" do
        expect(post.underline_thickness).to eq(50)
      end

      it "parses is_fixed_pitch" do
        expect(post.is_fixed_pitch).to eq(0)
      end

      it "parses min_mem_type42" do
        expect(post.min_mem_type42).to eq(0)
      end

      it "parses max_mem_type42" do
        expect(post.max_mem_type42).to eq(0)
      end

      it "parses min_mem_type1" do
        expect(post.min_mem_type1).to eq(0)
      end

      it "parses max_mem_type1" do
        expect(post.max_mem_type1).to eq(0)
      end
    end

    context "with custom values" do
      let(:data) do
        build_post_table(
          italic_angle: -15.5,
          underline_position: -150,
          underline_thickness: 75,
          is_fixed_pitch: 1,
          min_mem_type42: 1000,
          max_mem_type42: 2000,
          min_mem_type1: 500,
          max_mem_type1: 1500,
        )
      end
      let(:post) { described_class.read(data) }

      it "parses italic angle correctly" do
        expect(post.italic_angle).to be_within(0.01).of(-15.5)
      end

      it "parses underline position correctly" do
        expect(post.underline_position).to eq(-150)
      end

      it "parses underline thickness correctly" do
        expect(post.underline_thickness).to eq(75)
      end

      it "parses is_fixed_pitch as monospace flag" do
        expect(post.is_fixed_pitch).to eq(1)
      end

      it "parses memory limits correctly" do
        expect(post.min_mem_type42).to eq(1000)
        expect(post.max_mem_type42).to eq(2000)
        expect(post.min_mem_type1).to eq(500)
        expect(post.max_mem_type1).to eq(1500)
      end
    end

    context "with positive italic angle" do
      let(:data) { build_post_table(italic_angle: 12.5) }
      let(:post) { described_class.read(data) }

      it "handles positive italic angle" do
        expect(post.italic_angle).to be_within(0.01).of(12.5)
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid data" do
      data = build_post_table
      post = described_class.read(data)
      expect(post).to be_valid
    end

    it "handles nil data gracefully" do
      post = described_class.read(nil)
      expect(post).to be_valid
    end
  end

  describe "STANDARD_NAMES constant" do
    it "has exactly 258 names" do
      expect(described_class::STANDARD_NAMES.length).to eq(258)
    end

    it "starts with .notdef" do
      expect(described_class::STANDARD_NAMES[0]).to eq(".notdef")
    end

    it "includes all expected standard glyphs" do
      names = described_class::STANDARD_NAMES
      expect(names).to include(".notdef", ".null", "nonmarkingreturn")
      expect(names).to include("space", "A", "Z", "a", "z")
      expect(names).to include("zero", "one", "nine")
    end

    it "is frozen" do
      expect(described_class::STANDARD_NAMES).to be_frozen
    end
  end
end
