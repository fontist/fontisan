# frozen_string_literal: true

require "spec_helper"
require "fontisan/ucd/config"

RSpec.describe Fontisan::Ucd::Config do
  describe ".default_version" do
    it "returns a version string" do
      expect(described_class.default_version).to be_a(String)
      expect(described_class.default_version).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe ".known_versions" do
    it "includes the default version" do
      expect(described_class.known_versions).to include(described_class.default_version)
    end

    it "is an Array of strings" do
      expect(described_class.known_versions).to be_an(Array)
      expect(described_class.known_versions).to all(match(/\A\d+\.\d+\.\d+\z/))
    end
  end

  describe ".known?" do
    it "returns true for the default version" do
      expect(described_class.known?(described_class.default_version)).to be true
    end

    it "returns false for an unknown version" do
      expect(described_class.known?("0.0.0-never")).to be false
    end
  end

  describe ".base_url" do
    it "is a unicode.org URL" do
      expect(described_class.base_url).to start_with("https://")
      expect(described_class.base_url).to include("unicode.org")
    end
  end

  describe ".listing_url" do
    it "is a unicode.org URL" do
      expect(described_class.listing_url).to start_with("https://")
      expect(described_class.listing_url).to include("unicode.org")
    end
  end

  describe ".ucdxml_url_for" do
    it "builds a full URL for a version" do
      url = described_class.ucdxml_url_for("17.0.0")
      expect(url).to eq("#{described_class.base_url}/17.0.0/ucdxml/ucd.all.flat.zip")
    end
  end
end
