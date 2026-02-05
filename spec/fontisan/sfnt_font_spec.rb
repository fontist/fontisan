# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::SfntFont do
  describe ".from_file" do
    context "with valid TTF file" do
      it "returns an SfntFont instance" do
        ttf_path = fixture_path("fonts/Libertinus/Libertinus-7.051/static/TTF/LibertinusKeyboard-Regular.ttf")
        font = described_class.from_file(ttf_path)

        expect(font.class).to eq(described_class)
        expect(font).to respond_to(:header)
      end
    end

    context "with valid OTF file" do
      it "returns an SfntFont instance" do
        otf_path = fixture_path("fonts/SourceSans3/OTF/SourceSans3-Regular.otf")
        font = described_class.from_file(otf_path)

        expect(font.class).to eq(described_class)
        expect(font).to respond_to(:header)
      end
    end

    context "does not return a File object" do
      it "returns a font object, not File" do
        ttf_path = fixture_path("fonts/Libertinus/Libertinus-7.051/static/TTF/LibertinusKeyboard-Regular.ttf")
        font = described_class.from_file(ttf_path)

        expect(font.class).not_to eq(File)
        expect(font).not_to be_a(File)
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
