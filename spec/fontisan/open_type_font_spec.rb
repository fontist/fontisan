# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::OpenTypeFont do
  describe ".from_file" do
    context "with valid OTF file" do
      it "returns an OpenTypeFont instance" do
        otf_path = fixture_path("fonts/SourceSans3/OTF/SourceSans3-Regular.otf")
        font = described_class.from_file(otf_path)

        expect(font).to be_a(described_class)
      end

      it "sets the loading mode correctly" do
        otf_path = fixture_path("fonts/SourceSans3/OTF/SourceSans3-Regular.otf")
        font = described_class.from_file(otf_path, mode: Fontisan::LoadingModes::METADATA)

        expect(font.loading_mode).to eq(Fontisan::LoadingModes::METADATA)
      end

      it "returns false for truetype?" do
        otf_path = fixture_path("fonts/SourceSans3/OTF/SourceSans3-Regular.otf")
        font = described_class.from_file(otf_path)

        expect(font.truetype?).to be false
      end

      it "returns true for cff?" do
        otf_path = fixture_path("fonts/SourceSans3/OTF/SourceSans3-Regular.otf")
        font = described_class.from_file(otf_path)

        expect(font.cff?).to be true
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
        expect { described_class.from_file("nonexistent.otf") }
          .to raise_error(Errno::ENOENT, /File not found/)
      end
    end
  end
end
