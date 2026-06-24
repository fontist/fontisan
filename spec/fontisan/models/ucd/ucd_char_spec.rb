# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/ucd"

RSpec.describe Fontisan::Models::Ucd::UcdChar do
  describe "XML parsing" do
    let(:xml) do
      <<~XML
        <char cp="0041" name="LATIN CAPITAL LETTER A" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/>
      XML
    end

    it "parses a single char element" do
      char = described_class.from_xml(xml)
      expect(char.cp).to eq("0041")
      expect(char.name).to eq("LATIN CAPITAL LETTER A")
      expect(char.general_category).to eq("Lu")
      expect(char.script).to eq("Latin")
      expect(char.block).to eq("Basic Latin")
      expect(char.age).to eq("1.1")
    end

    describe "#range?" do
      it "returns false for a single char" do
        char = described_class.from_xml(xml)
        expect(char.range?).to be false
      end

      it "returns true for a char with first_cp/last_cp" do
        range_xml = <<~XML
          <char first-cp="0000" last-cp="001F" name="<control>" general-category="Cc" script="Common" block="Basic Latin" age="1.1"/>
        XML
        char = described_class.from_xml(range_xml)
        expect(char.range?).to be true
        expect(char.first_cp).to eq("0000")
        expect(char.last_cp).to eq("001F")
      end
    end
  end
end
