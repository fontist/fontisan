# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Validators::ProfileLoader do
  describe ".load" do
    it "loads BasicValidator for indexability profile" do
      validator = described_class.load(:indexability)
      expect(validator).to be_a(Fontisan::Validators::BasicValidator)
    end

    it "loads FontBookValidator for usability profile" do
      validator = described_class.load(:usability)
      expect(validator).to be_a(Fontisan::Validators::FontBookValidator)
    end

    it "loads OpenTypeValidator for production profile" do
      validator = described_class.load(:production)
      expect(validator).to be_a(Fontisan::Validators::OpenTypeValidator)
    end

    it "loads WebFontValidator for web profile" do
      validator = described_class.load(:web)
      expect(validator).to be_a(Fontisan::Validators::WebFontValidator)
    end

    it "loads OpenTypeValidator for spec_compliance profile" do
      validator = described_class.load(:spec_compliance)
      expect(validator).to be_a(Fontisan::Validators::OpenTypeValidator)
    end

    it "loads OpenTypeValidator for default profile" do
      validator = described_class.load(:default)
      expect(validator).to be_a(Fontisan::Validators::OpenTypeValidator)
    end

    it "accepts string profile names" do
      validator = described_class.load("indexability")
      expect(validator).to be_a(Fontisan::Validators::BasicValidator)
    end

    it "raises ArgumentError for unknown profile" do
      expect {
        described_class.load(:unknown_profile)
      }.to raise_error(ArgumentError, /Unknown profile: unknown_profile/)
    end

    it "includes available profiles in error message" do
      expect {
        described_class.load(:invalid)
      }.to raise_error(ArgumentError, /Available profiles:/)
    end
  end

  describe ".available_profiles" do
    it "returns array of profile names" do
      profiles = described_class.available_profiles
      expect(profiles).to be_an(Array)
      expect(profiles.length).to eq(6)
    end

    it "includes all defined profiles" do
      profiles = described_class.available_profiles
      expect(profiles).to include(:indexability)
      expect(profiles).to include(:usability)
      expect(profiles).to include(:production)
      expect(profiles).to include(:web)
      expect(profiles).to include(:spec_compliance)
      expect(profiles).to include(:default)
    end
  end

  describe ".profile_info" do
    it "returns profile configuration for valid profile" do
      info = described_class.profile_info(:indexability)
      expect(info).to be_a(Hash)
      expect(info[:name]).to eq("Font Indexability")
      expect(info[:validator]).to eq("BasicValidator")
      expect(info[:loading_mode]).to eq("metadata")
    end

    it "returns profile configuration for production" do
      info = described_class.profile_info(:production)
      expect(info[:name]).to eq("Production Quality")
      expect(info[:validator]).to eq("OpenTypeValidator")
      expect(info[:loading_mode]).to eq("full")
      expect(info[:severity_threshold]).to eq("warning")
    end

    it "returns profile configuration for web" do
      info = described_class.profile_info(:web)
      expect(info[:name]).to eq("Web Font Readiness")
      expect(info[:validator]).to eq("WebFontValidator")
    end

    it "returns nil for unknown profile" do
      info = described_class.profile_info(:unknown)
      expect(info).to be_nil
    end

    it "accepts string profile names" do
      info = described_class.profile_info("indexability")
      expect(info).not_to be_nil
      expect(info[:name]).to eq("Font Indexability")
    end
  end

  describe ".all_profiles" do
    it "returns all profile configurations" do
      profiles = described_class.all_profiles
      expect(profiles).to be_a(Hash)
      expect(profiles.keys.length).to eq(6)
    end

    it "includes configuration for each profile" do
      profiles = described_class.all_profiles

      profiles.each do |name, config|
        expect(config).to have_key(:name)
        expect(config).to have_key(:description)
        expect(config).to have_key(:validator)
        expect(config).to have_key(:loading_mode)
        expect(config).to have_key(:severity_threshold)
      end
    end
  end

  describe "profile configurations" do
    it "configures indexability for fast scanning" do
      info = described_class.profile_info(:indexability)
      expect(info[:loading_mode]).to eq("metadata")
      expect(info[:severity_threshold]).to eq("error")
    end

    it "configures production for comprehensive checks" do
      info = described_class.profile_info(:production)
      expect(info[:loading_mode]).to eq("full")
      expect(info[:severity_threshold]).to eq("warning")
    end

    it "configures default as alias for production" do
      default_info = described_class.profile_info(:default)
      production_info = described_class.profile_info(:production)

      expect(default_info[:validator]).to eq(production_info[:validator])
      expect(default_info[:loading_mode]).to eq(production_info[:loading_mode])
    end
  end
end
