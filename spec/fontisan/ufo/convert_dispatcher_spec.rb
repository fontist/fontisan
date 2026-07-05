# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/convert"

# Phase 3 of issue #46: the UFO Convert dispatcher + per-format
# wrappers. These specs verify the dispatcher contract (registry
# contents, unknown-format handling) and the wrapper modules'
# structural shape. Actual end-to-end compilation through each
# compiler is covered by convert_spec.rb (which loads real UFO
# fixtures) — these specs don't repeat that work.
RSpec.describe Fontisan::Ufo::Convert do
  describe "COMPILER_FOR_FORMAT" do
    it "maps every 1-step output format to a compiler class" do
      expect(described_class::COMPILER_FOR_FORMAT).to eq(
        ttf: Fontisan::Ufo::Compile::TtfCompiler,
        otf: Fontisan::Ufo::Compile::OtfCompiler,
        otf2: Fontisan::Ufo::Compile::Otf2Compiler,
      )
    end

    it "is frozen" do
      expect(described_class::COMPILER_FOR_FORMAT).to be_frozen
    end
  end

  describe "WRAPPER_FOR_FORMAT" do
    it "maps every 2-step output format to a wrapper module" do
      expect(described_class::WRAPPER_FOR_FORMAT).to eq(
        woff: Fontisan::Ufo::Convert::ToWoff,
        woff2: Fontisan::Ufo::Convert::ToWoff2,
        dfont: Fontisan::Ufo::Convert::ToDfont,
        ttc: Fontisan::Ufo::Convert::ToTtc,
        otc: Fontisan::Ufo::Convert::ToOtc,
        pfb: Fontisan::Ufo::Convert::ToPfb,
        pfa: Fontisan::Ufo::Convert::ToPfa,
      )
    end

    it "is frozen" do
      expect(described_class::WRAPPER_FOR_FORMAT).to be_frozen
    end

    it "is disjoint from COMPILER_FOR_FORMAT" do
      compiler_keys = described_class::COMPILER_FOR_FORMAT.keys
      wrapper_keys = described_class::WRAPPER_FOR_FORMAT.keys
      expect(compiler_keys & wrapper_keys).to be_empty
    end
  end

  describe ".convert" do
    let(:ufo) { Fontisan::Ufo::Font.new }

    it "raises ArgumentError for unknown formats" do
      expect do
        described_class.convert(ufo, to: :unknown, output_path: "/tmp/out.unknown")
      end.to raise_error(ArgumentError, /unknown UFO output format/)
    end
  end
end

# Per-format wrappers: thin facades. Verify they exist, are modules,
# and respond to .convert.
[
  Fontisan::Ufo::Convert::ToTtf,
  Fontisan::Ufo::Convert::ToOtf,
  Fontisan::Ufo::Convert::ToOtf2,
  Fontisan::Ufo::Convert::ToWoff,
  Fontisan::Ufo::Convert::ToWoff2,
  Fontisan::Ufo::Convert::ToDfont,
  Fontisan::Ufo::Convert::ToTtc,
  Fontisan::Ufo::Convert::ToOtc,
  Fontisan::Ufo::Convert::ToPfb,
  Fontisan::Ufo::Convert::ToPfa,
].each do |wrapper|
  RSpec.describe wrapper, "structural shape" do
    it "is a module under Ufo::Convert" do
      expect(wrapper).to be_a(Module)
      expect(wrapper.name).to start_with("Fontisan::Ufo::Convert::")
    end

    it "responds to .convert" do
      expect(wrapper).to respond_to(:convert)
    end
  end
end
