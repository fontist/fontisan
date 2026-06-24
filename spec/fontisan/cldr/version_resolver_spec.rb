# frozen_string_literal: true

require "spec_helper"
require "fontisan/cldr/version_resolver"
require "fontisan/cldr/unknown_version_error"

RSpec.describe Fontisan::Cldr::VersionResolver do
  describe ".resolve" do
    it "returns the default version for nil" do
      expect(described_class.resolve(nil))
        .to eq(Fontisan::Cldr::Config.default_version)
    end

    it "returns the default version for :default" do
      expect(described_class.resolve(:default))
        .to eq(Fontisan::Cldr::Config.default_version)
    end

    it "returns a known explicit version" do
      version = Fontisan::Cldr::Config.known_versions.first
      expect(described_class.resolve(version)).to eq(version)
    end

    it "raises UnknownVersionError for an unknown version" do
      expect { described_class.resolve("0.0.0-never") }
        .to raise_error(Fontisan::Cldr::UnknownVersionError, /not recognized/)
    end
  end

  describe ".validate!" do
    it "does not raise for a known version" do
      expect { described_class.validate!(Fontisan::Cldr::Config.default_version) }
        .not_to raise_error
    end

    it "raises UnknownVersionError for an unknown version" do
      expect { described_class.validate!("0.0.0-nope") }
        .to raise_error(Fontisan::Cldr::UnknownVersionError)
    end

    it "names the known versions in the error message" do
      expect { described_class.validate!("0.0.0-nope") }
        .to raise_error(Fontisan::Cldr::UnknownVersionError, /Known versions:/)
    end
  end
end
