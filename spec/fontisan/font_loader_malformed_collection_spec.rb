# frozen_string_literal: true

require "spec_helper"
require "tempfile"

# Regression tests for malformed TTC/OTC files. Two specific failure modes
# were observed in earlier branches:
#
#   1. A `ttcf` whose inner SFNT version was an unrecognised tag (e.g. "ZZZZ")
#      was accepted: detect_format said :ttc, load_collection returned a
#      TrueTypeCollection. Earlier (main-branch) load_collection rejected
#      these with InvalidFontError.
#
#   2. A `ttcf` whose inner-font offset pointed past EOF crashed deep in the
#      loader with `NoMethodError: undefined method 'unpack1' for nil` instead
#      of raising InvalidFontError.
#
# Both are now rejected up front: detect_format returns nil for any ttcf with
# unreadable offsets or unrecognised inner SFNT versions, and load /
# load_collection raise InvalidFontError.
RSpec.describe Fontisan::FontLoader do
  def write_fake_ttcf(inner_payload, offset: 16, num_fonts: 1, num_offsets: 1)
    file = Tempfile.new(["fake-ttc", ".ttc"])
    file.binmode
    file.write("ttcf")
    file.write([0x00010000].pack("N"))     # version 1.0
    file.write([num_fonts].pack("N"))      # num_fonts
    num_offsets.times { file.write([offset].pack("N")) }
    file.write(inner_payload)
    file.flush
    file
  end

  describe "ttcf with an unrecognised inner SFNT version" do
    let(:file) { write_fake_ttcf("ZZZZ") }

    after { file.close! }

    it "detect_format returns nil — an unrecognised inner SFNT version is not a loadable collection" do
      expect(described_class.detect_format(file.path)).to be_nil
    end

    it "load_collection raises InvalidFontError instead of returning a TrueTypeCollection" do
      expect { described_class.load_collection(file.path) }
        .to raise_error(Fontisan::InvalidFontError)
    end

    it "load raises InvalidFontError instead of returning a font" do
      expect { described_class.load(file.path) }
        .to raise_error(Fontisan::InvalidFontError)
    end
  end

  describe "ttcf with an inner-font offset past EOF" do
    let(:file) { write_fake_ttcf("", offset: 999_999) }

    after { file.close! }

    it "detect_format returns nil — an unreadable inner offset is not a valid TTC" do
      expect(described_class.detect_format(file.path)).to be_nil
    end

    it "load raises InvalidFontError, not NoMethodError" do
      expect { described_class.load(file.path) }
        .to raise_error(Fontisan::InvalidFontError)
    end

    it "load_collection raises InvalidFontError" do
      expect { described_class.load_collection(file.path) }
        .to raise_error(Fontisan::InvalidFontError)
    end
  end

  describe "ttcf with a valid OTTO offset followed by an offset past EOF" do
    # Two offsets: first points at "OTTO", second points past EOF. The first
    # offset alone would suggest :otc, but the second offset is unreadable,
    # so detect_collection_type must scan every offset and return nil.
    let(:file) do
      f = Tempfile.new(["fake-mixed-otc", ".ttc"])
      f.binmode
      f.write("ttcf")
      f.write([0x00010000].pack("N"))    # version 1.0
      f.write([2].pack("N"))             # num_fonts = 2
      f.write([24].pack("N"))            # offset 0 -> inner OTTO payload
      f.write([999_999].pack("N"))       # offset 1 -> past EOF
      f.write("OTTO")
      f.flush
      f
    end

    after { file.close! }

    it "detect_format returns nil instead of :otc when a later offset is unreadable" do
      expect(described_class.detect_format(file.path)).to be_nil
    end

    it "load raises InvalidFontError instead of falling through to a loader" do
      expect { described_class.load(file.path) }
        .to raise_error(Fontisan::InvalidFontError)
    end
  end

  describe "ttcf with a truncated header (num_fonts says 4 but only 1 offset present)" do
    let(:file) { write_fake_ttcf("", num_fonts: 4, num_offsets: 1) }

    after { file.close! }

    it "detect_format returns nil for the truncated header" do
      expect(described_class.detect_format(file.path)).to be_nil
    end

    it "load_collection raises InvalidFontError" do
      expect { described_class.load_collection(file.path) }
        .to raise_error(Fontisan::InvalidFontError)
    end
  end
end
