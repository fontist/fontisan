# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"

RSpec.describe Fontisan::Stitcher::GlyphLimit do
  describe ".for_format" do
    it "returns 65,535 for :ttf" do
      expect(described_class.for_format(:ttf)).to eq(65_535)
    end

    it "returns 65,535 for :otf (CFF1 also caps at 65,535)" do
      expect(described_class.for_format(:otf)).to eq(65_535)
    end

    it "raises ArgumentError for unknown format" do
      expect { described_class.for_format(:woff) }
        .to raise_error(ArgumentError, /unknown format/)
    end
  end

  describe ".check!" do
    it "does nothing when glyph count is under the TTF cap" do
      expect { described_class.check!(65_535, format: :ttf) }.not_to raise_error
    end

    it "raises GlyphLimitExceededError when TTF cap is exceeded" do
      expect { described_class.check!(65_536, format: :ttf) }
        .to raise_error(Fontisan::GlyphLimitExceededError, /65536 unique glyphs/)
    end

    it "raises GlyphLimitExceededError when OTF cap is exceeded" do
      expect { described_class.check!(100_000, format: :otf) }
        .to raise_error(Fontisan::GlyphLimitExceededError, /100000 unique glyphs/)
    end

    it "includes actionable guidance in the error message" do
      expect { described_class.check!(100_000, format: :ttf) }
        .to raise_error(Fontisan::GlyphLimitExceededError, /TTC/)
    end
  end
end
