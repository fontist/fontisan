# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/ucd"

RSpec.describe Fontisan::Models::Ucd::Ucd do
  describe "XML parsing" do
    let(:xml) do
      <<~XML
        <ucd>
          <description>Unicode Character Database</description>
          <char cp="0041" name="LATIN CAPITAL LETTER A" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/>
          <char cp="0042" name="LATIN CAPITAL LETTER B" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/>
          <char first-cp="0000" last-cp="001F" name="<control>" general-category="Cc" script="Common" block="Basic Latin" age="1.1"/>
        </ucd>
      XML
    end

    it "parses all char children" do
      ucd = described_class.from_xml(xml)
      chars = ucd.chars
      expect(chars.length).to eq(3)
    end

    it "preserves char attributes" do
      ucd = described_class.from_xml(xml)
      chars = ucd.chars
      first = chars[0]
      expect(first.cp).to eq("0041")
      expect(first.name).to eq("LATIN CAPITAL LETTER A")
    end

    it "exposes both single and range chars" do
      ucd = described_class.from_xml(xml)
      chars = ucd.chars
      ranges, singles = chars.partition(&:range?)
      expect(singles.length).to eq(2)
      expect(ranges.length).to eq(1)
    end
  end
end
