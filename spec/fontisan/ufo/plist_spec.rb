# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/plist"

RSpec.describe Fontisan::Ufo::Plist do
  describe ".parse / .emit" do
    it "round-trips a simple dict" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
          <dict>
            <key>familyName</key>
            <string>Last Resort</string>
            <key>unitsPerEm</key>
            <integer>1024</integer>
            <key>italicAngle</key>
            <real>0.0</real>
            <key>openTypeOS2WeightClass</key>
            <integer>400</integer>
          </dict>
        </plist>
      XML

      hash = described_class.parse(xml)
      expect(hash).to eq(
        "familyName" => "Last Resort",
        "unitsPerEm" => 1024,
        "italicAngle" => 0.0,
        "openTypeOS2WeightClass" => 400,
      )

      out = described_class.emit(hash)
      re = described_class.parse(out)
      expect(re).to eq(hash)
    end

    it "handles nested dicts and arrays" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
          <dict>
            <key>glyphs</key>
            <array>
              <string>A</string>
              <string>B</string>
              <integer>42</integer>
            </array>
            <key>nested</key>
            <dict>
              <key>inner</key>
              <string>value</string>
            </dict>
          </dict>
        </plist>
      XML

      hash = described_class.parse(xml)
      expect(hash["glyphs"]).to eq(["A", "B", 42])
      expect(hash["nested"]).to eq("inner" => "value")
    end

    it "handles boolean values" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
          <dict>
            <key>yes</key><true/>
            <key>no</key><false/>
          </dict>
        </plist>
      XML

      expect(described_class.parse(xml)).to eq("yes" => true, "no" => false)
    end

    it "raises on malformed XML" do
      expect { described_class.parse("<not-plist/>") }.to raise_error(Fontisan::Ufo::Plist::ParseError)
    end
  end
end
