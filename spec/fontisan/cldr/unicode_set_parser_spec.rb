# frozen_string_literal: true

require "spec_helper"
require "fontisan/cldr/unicode_set_parser"

RSpec.describe Fontisan::Cldr::UnicodeSetParser do
  describe ".call with single chars" do
    it "returns a sorted, deduplicated codepoint array" do
      expect(described_class.call("[abc]")).to eq([97, 98, 99])
    end

    it "handles non-ASCII chars" do
      expect(described_class.call("[aà]")).to eq([97, 224])
    end

    it "deduplicates" do
      expect(described_class.call("[aab]")).to eq([97, 98])
    end

    it "sorts in codepoint order regardless of input order" do
      expect(described_class.call("[cba]")).to eq([97, 98, 99])
    end
  end

  describe ".call with ranges" do
    it "expands a basic ASCII range" do
      expect(described_class.call("[a-z]").length).to eq(26)
      expect(described_class.call("[a-z]").first(3)).to eq([97, 98, 99])
    end

    it "expands an uppercase range" do
      expect(described_class.call("[A-Z]").length).to eq(26)
      expect(described_class.call("[A-Z]").first).to eq(65)
    end

    it "combines ranges and single chars" do
      cps = described_class.call("[A-Za-z]")
      expect(cps.length).to eq(52)
      expect(cps.first(3)).to eq([65, 66, 67])
    end

    it "expands a Latin-1 Supplement range" do
      expect(described_class.call("[\\u00C0-\\u00C5]"))
        .to eq([192, 193, 194, 195, 196, 197])
    end
  end

  describe ".call with escapes" do
    it "parses \\uXXXX" do
      expect(described_class.call("[\\u00E9]")).to eq([233]) # é
    end

    it "parses \\UXXXXXXXX (supplementary plane)" do
      expect(described_class.call("[\\U0001F600]")).to eq([0x1F600]) # 😀
    end

    it "parses \\u{...} variable-length form" do
      expect(described_class.call("[\\u{1F600}]")).to eq([0x1F600])
    end

    it "treats backslash-escaped special chars as literals" do
      expect(described_class.call("[\\^]").first).to eq(0x5E)
    end
  end

  describe ".call with negation" do
    it "inverts against 0..0x10FFFF" do
      cps = described_class.call("[^a]")
      expect(cps.length).to eq(0x110000 - 1)
      expect(cps).not_to include(97)
      expect(cps.first).to eq(0)
    end

    it "excludes every codepoint in the body" do
      cps = described_class.call("[^abc]")
      expect(cps).not_to include(97, 98, 99)
      expect(cps.length).to eq(0x110000 - 3)
    end
  end

  describe ".call error handling" do
    it "raises ParseError when input is not bracketed" do
      expect { described_class.call("abc") }
        .to raise_error(Fontisan::Cldr::UnicodeSetParser::ParseError,
                        /bracketed/)
    end

    it "raises ParseError on nested set syntax" do
      expect { described_class.call("[a[b]]") }
        .to raise_error(Fontisan::Cldr::UnicodeSetParser::ParseError, /nested/)
    end

    it "raises ParseError on property syntax" do
      expect { described_class.call("[:Latin:]") }
        .to raise_error(Fontisan::Cldr::UnicodeSetParser::ParseError,
                        /property/)
    end

    it "raises ParseError on named sequence syntax" do
      expect { described_class.call("[{abc}]") }
        .to raise_error(Fontisan::Cldr::UnicodeSetParser::ParseError,
                        /named sequence/)
    end

    it "raises ParseError on a dangling range operator" do
      expect { described_class.call("[-a]") }
        .to raise_error(Fontisan::Cldr::UnicodeSetParser::ParseError,
                        /dangling/)
    end
  end
end
