# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::TrueTypeFont do
  describe ".from_file" do
    context "with valid TTF file" do
      it "returns a TrueTypeFont instance" do
        ttf_path = fixture_path("fonts/Libertinus/Libertinus-7.051/static/TTF/LibertinusKeyboard-Regular.ttf")
        font = described_class.from_file(ttf_path)

        expect(font).to be_a(described_class)
      end

      it "sets the loading mode correctly" do
        ttf_path = fixture_path("fonts/Libertinus/Libertinus-7.051/static/TTF/LibertinusKeyboard-Regular.ttf")
        font = described_class.from_file(ttf_path, mode: Fontisan::LoadingModes::METADATA)

        expect(font.loading_mode).to eq(Fontisan::LoadingModes::METADATA)
      end

      it "returns true for truetype?" do
        ttf_path = fixture_path("fonts/Libertinus/Libertinus-7.051/static/TTF/LibertinusKeyboard-Regular.ttf")
        font = described_class.from_file(ttf_path)

        expect(font.truetype?).to be true
      end

      it "returns false for cff?" do
        ttf_path = fixture_path("fonts/Libertinus/Libertinus-7.051/static/TTF/LibertinusKeyboard-Regular.ttf")
        font = described_class.from_file(ttf_path)

        expect(font.cff?).to be false
      end
    end

    context "with invalid inputs" do
      it "raises ArgumentError when path is nil" do
        expect { described_class.from_file(nil) }
          .to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises ArgumentError when path is empty" do
        expect { described_class.from_file("") }
          .to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises Errno::ENOENT when file does not exist" do
        expect { described_class.from_file("nonexistent.ttf") }
          .to raise_error(Errno::ENOENT, /File not found/)
      end
    end
  end
end
