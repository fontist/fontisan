# frozen_string_literal: true

RSpec.describe Fontisan::Type1::AFMParser, "with real AFM files" do
  describe "loading AFM format" do
    let(:afm_path) do
      File.expand_path("../../fixtures/fonts/type1/matrix.afm", __dir__)
    end
    let(:afm) do
      described_class.parse_file(afm_path)
    end

    it "loads AFM file successfully" do
      expect(afm).to be_a(described_class)
    end

    it "extracts font name from AFM" do
      expect(afm.font_name).not_to be_nil
    end

    it "has character widths" do
      expect(afm.character_widths).to be_a(Hash)
      expect(afm.character_widths.count).to be > 0
    end

    it "has kerning pairs" do
      expect(afm.kerning_pairs).to be_a(Hash)
      # Kerning pairs may be empty in some fonts
    end

    it "provides width for character" do
      # Check a common character
      expect(afm.has_character?("A")).to be true
      width = afm.width("A")
      expect(width).to be_a(Integer)
      expect(width).to be > 0
    end

    it "provides kerning adjustment" do
      # Kerning may or may not exist
      afm.kerning_pairs.each do |(left, right), adjustment|
        expect(afm.kerning(left, right)).to eq(adjustment)
      end
    end
  end

  describe "parse from string" do
    it "parses AFM content from string" do
      afm_content = <<~AFM
        StartFontMetrics 2.0
        FontName TestFont
        FullName Test Font
        FamilyName Test
        Weight Regular
        Version 1.0
        Notice Copyright 2024
        FontBBox -100 -200 1000 1200
        StartCharMetrics 5
        C 65 ; WX 600 ; N A ; B 0 0 600 700
        C 66 ; WX 550 ; N B ; B 0 0 550 700
        C 67 ; WX 600 ; N C ; B 0 0 600 700
        C 68 ; WX 600 ; N D ; B 0 0 600 700
        C 69 ; WX 550 ; N E ; B 0 0 550 700
        EndCharMetrics
        StartKernData
        StartKernPairs 1
        KPX A V -50
        EndKernPairs
        EndKernData
        EndFontMetrics
      AFM

      afm = described_class.parse(afm_content)

      expect(afm.font_name).to eq("TestFont")
      expect(afm.full_name).to eq("Test Font")
      expect(afm.family_name).to eq("Test")
      expect(afm.weight).to eq("Regular")
      expect(afm.version).to eq("1.0")
      expect(afm.copyright).to eq("Copyright 2024")
      expect(afm.font_bbox).to eq([-100, -200, 1000, 1200])

      # Character widths
      expect(afm.width("A")).to eq(600)
      expect(afm.width("B")).to eq(550)
      expect(afm.width("E")).to eq(550)

      # Character bounding boxes
      expect(afm.character_bboxes["A"]).to eq({ llx: 0, lly: 0, urx: 600,
                                                ury: 700 })

      # Kerning pairs
      expect(afm.kerning("A", "V")).to eq(-50)
    end

    it "handles AFM without kerning data" do
      afm_content = <<~AFM
        StartFontMetrics 2.0
        FontName SimpleFont
        StartCharMetrics 2
        C 65 ; WX 500 ; N A ; B 0 0 500 700
        C 66 ; WX 500 ; N B ; B 0 0 500 700
        EndCharMetrics
        EndFontMetrics
      AFM

      afm = described_class.parse(afm_content)

      expect(afm.font_name).to eq("SimpleFont")
      expect(afm.character_widths.count).to eq(2)
      expect(afm.kerning_pairs).to be_empty
    end
  end

  describe "error handling" do
    it "raises error for nil path" do
      expect { described_class.parse_file(nil) }
        .to raise_error(ArgumentError, /Path cannot be nil/)
    end

    it "raises error for missing file" do
      expect { described_class.parse_file("nonexistent.afm") }
        .to raise_error(Fontisan::Error, /AFM file not found/)
    end
  end

  describe "AFM file support" do
    let(:afm_path) do
      File.expand_path("../../fixtures/fonts/type1/matrix.afm", __dir__)
    end

    it "AFM file exists for reference" do
      expect(File.exist?(afm_path)).to be true
    end

    it "contains valid AFM data" do
      content = File.read(afm_path)
      expect(content).to start_with("StartFontMetrics")
      expect(content).to include("FontName")
      expect(content).to include("EncodingScheme")
    end
  end
end
