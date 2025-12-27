# frozen_string_literal: true

require "spec_helper"
require "fontisan/pipeline/format_detector"

RSpec.describe Fontisan::Pipeline::FormatDetector do
  # Helper to get fixture path
  def fixture_font_path(filename)
    File.join(File.dirname(__FILE__), "../../fixtures/fonts", filename)
  end

  describe "#initialize" do
    let(:file_path) { fixture_font_path("NotoSans-Regular.ttf") }
    let(:detector) { described_class.new(file_path) }

    it "initializes with file path" do
      expect(detector.file_path).to eq(file_path)
    end

    it "initializes with nil font" do
      expect(detector.font).to be_nil
    end
  end

  describe "#detect_format" do
    context "with TrueType font" do
      let(:file_path) { fixture_font_path("NotoSans-Regular.ttf") }
      let(:detector) { described_class.new(file_path) }

      it "detects TTF format" do
        detector.detect
        expect(detector.detect_format).to eq(:ttf)
      end
    end

    context "with OpenType font" do
      let(:file_path) { fixture_font_path("MonaSans/fonts/static/otf/MonaSans-Regular.otf") }
      let(:detector) { described_class.new(file_path) }

      it "detects OTF format" do
        detector.detect
        expect(detector.detect_format).to eq(:otf)
      end
    end

    context "with OpenType Collection" do
      let(:file_path) { fixture_font_path("NotoSerifCJK/NotoSerifCJK.ttc") }
      let(:detector) { described_class.new(file_path) }

      it "detects OTC format" do
        detector.detect
        expect(detector.detect_format).to eq(:otc)
      end
    end

    context "with SVG font" do
      let(:file_path) { "font.svg" }
      let(:detector) { described_class.new(file_path) }

      it "detects SVG format from extension" do
        detector.detect
        expect(detector.detect_format).to eq(:svg)
      end
    end

    context "with unknown font" do
      let(:file_path) { "nonexistent.xyz" }
      let(:detector) { described_class.new(file_path) }

      it "detects unknown format" do
        detector.detect
        expect(detector.detect_format).to eq(:unknown)
      end
    end
  end

  describe "#detect_variation" do
    context "with static TTF font" do
      let(:file_path) { fixture_font_path("NotoSans-Regular.ttf") }
      let(:detector) { described_class.new(file_path) }

      it "detects static variation type" do
        result = detector.detect
        expect(result[:variation_type]).to eq(:static)
      end
    end

    context "with static OTF font" do
      let(:file_path) { fixture_font_path("MonaSans/fonts/static/otf/MonaSans-Regular.otf") }
      let(:detector) { described_class.new(file_path) }

      it "detects static variation type" do
        result = detector.detect
        expect(result[:variation_type]).to eq(:static)
      end
    end

    context "with TrueType variable font (gvar)" do
      let(:file_path) { fixture_font_path("MonaSans/fonts/variable/MonaSansVF[wdth,wght,opsz].ttf") }
      let(:detector) { described_class.new(file_path) }

      it "detects gvar variation type" do
        result = detector.detect
        expect(result[:variation_type]).to eq(:gvar)
      end
    end

    context "with collection" do
      let(:file_path) { fixture_font_path("NotoSerifCJK/NotoSerifCJK.ttc") }
      let(:detector) { described_class.new(file_path) }

      it "detects static for collection" do
        result = detector.detect
        expect(result[:variation_type]).to eq(:static)
      end
    end
  end

  describe "#detect_capabilities" do
    context "with TrueType font" do
      let(:file_path) { fixture_font_path("NotoSans-Regular.ttf") }
      let(:detector) { described_class.new(file_path) }

      it "detects truetype outline type" do
        result = detector.detect
        expect(result[:capabilities][:outline]).to eq(:truetype)
      end

      it "detects no variation support" do
        result = detector.detect
        expect(result[:capabilities][:variation]).to be false
      end

      it "detects no collection support" do
        result = detector.detect
        expect(result[:capabilities][:collection]).to be false
      end

      it "lists available tables" do
        result = detector.detect
        expect(result[:capabilities][:tables]).to include("glyf", "head", "name")
      end
    end

    context "with OpenType/CFF font" do
      let(:file_path) { fixture_font_path("MonaSans/fonts/static/otf/MonaSans-Regular.otf") }
      let(:detector) { described_class.new(file_path) }

      it "detects CFF outline type" do
        result = detector.detect
        expect(result[:capabilities][:outline]).to eq(:cff)
      end

      it "lists CFF table" do
        result = detector.detect
        expect(result[:capabilities][:tables]).to include("CFF ")
      end
    end

    context "with variable font" do
      let(:file_path) { fixture_font_path("MonaSans/fonts/variable/MonaSansVF[wdth,wght,opsz].ttf") }
      let(:detector) { described_class.new(file_path) }

      it "detects variation support" do
        result = detector.detect
        expect(result[:capabilities][:variation]).to be true
      end

      it "lists variation tables" do
        result = detector.detect
        expect(result[:capabilities][:tables]).to include("fvar", "gvar")
      end
    end

    context "with collection" do
      let(:file_path) { fixture_font_path("NotoSerifCJK/NotoSerifCJK.ttc") }
      let(:detector) { described_class.new(file_path) }

      it "detects collection support" do
        result = detector.detect
        expect(result[:capabilities][:collection]).to be true
      end
    end
  end

  describe "#collection?" do
    context "with TrueType Collection" do
      let(:file_path) { fixture_font_path("NotoSerifCJK/NotoSerifCJK.ttc") }
      let(:detector) { described_class.new(file_path) }

      it "returns true" do
        detector.detect
        expect(detector.collection?).to be true
      end
    end

    context "with single font" do
      let(:file_path) { fixture_font_path("NotoSans-Regular.ttf") }
      let(:detector) { described_class.new(file_path) }

      it "returns false" do
        detector.detect
        expect(detector.collection?).to be false
      end
    end
  end

  describe "#variable?" do
    context "with variable font" do
      let(:file_path) { fixture_font_path("MonaSans/fonts/variable/MonaSansVF[wdth,wght,opsz].ttf") }
      let(:detector) { described_class.new(file_path) }

      it "returns true" do
        detector.detect
        expect(detector.variable?).to be true
      end
    end

    context "with static font" do
      let(:file_path) { fixture_font_path("NotoSans-Regular.ttf") }
      let(:detector) { described_class.new(file_path) }

      it "returns false" do
        detector.detect
        expect(detector.variable?).to be false
      end
    end
  end

  describe "#compatible_with?" do
    context "with static TTF font" do
      let(:file_path) { fixture_font_path("NotoSans-Regular.ttf") }
      let(:detector) { described_class.new(file_path) }

      it "is compatible with same format" do
        detector.detect
        expect(detector.compatible_with?(:ttf)).to be true
      end

      it "is compatible with any format for static fonts" do
        detector.detect
        expect(detector.compatible_with?(:otf)).to be true
        expect(detector.compatible_with?(:woff)).to be true
        expect(detector.compatible_with?(:woff2)).to be true
        expect(detector.compatible_with?(:svg)).to be true
      end
    end

    context "with gvar variable font" do
      let(:file_path) { fixture_font_path("MonaSans/fonts/variable/MonaSansVF[wdth,wght,opsz].ttf") }
      let(:detector) { described_class.new(file_path) }

      it "is compatible with TrueType formats" do
        detector.detect
        expect(detector.compatible_with?(:ttf)).to be true
        expect(detector.compatible_with?(:woff)).to be true
        expect(detector.compatible_with?(:woff2)).to be true
      end

      it "is not compatible with OTF" do
        detector.detect
        expect(detector.compatible_with?(:otf)).to be false
      end
    end
  end

  describe "#detect" do
    let(:file_path) { fixture_font_path("NotoSans-Regular.ttf") }
    let(:detector) { described_class.new(file_path) }

    it "returns hash with all detection results" do
      result = detector.detect

      expect(result).to be_a(Hash)
      expect(result).to have_key(:format)
      expect(result).to have_key(:variation_type)
      expect(result).to have_key(:capabilities)
    end

    it "detects format" do
      result = detector.detect
      expect(result[:format]).to eq(:ttf)
    end

    it "detects variation type" do
      result = detector.detect
      expect(result[:variation_type]).to eq(:static)
    end

    it "detects capabilities" do
      result = detector.detect
      expect(result[:capabilities]).to be_a(Hash)
      expect(result[:capabilities]).to have_key(:outline)
      expect(result[:capabilities]).to have_key(:variation)
      expect(result[:capabilities]).to have_key(:collection)
      expect(result[:capabilities]).to have_key(:tables)
    end

    context "with detailed capabilities check" do
      it "provides correct outline type" do
        result = detector.detect
        expect(result[:capabilities][:outline]).to eq(:truetype)
      end

      it "provides correct variation status" do
        result = detector.detect
        expect(result[:capabilities][:variation]).to be false
      end

      it "provides correct collection status" do
        result = detector.detect
        expect(result[:capabilities][:collection]).to be false
      end

      it "provides table list" do
        result = detector.detect
        expect(result[:capabilities][:tables]).to be_an(Array)
        expect(result[:capabilities][:tables]).not_to be_empty
      end
    end
  end
end
