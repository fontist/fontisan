# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg_to_glyf"

RSpec.describe Fontisan::SvgToGlyf::Path::Parser do
  let(:command_type) { Fontisan::SvgToGlyf::Path::Command }

  describe ".parse" do
    it "parses a simple M-L-Z path" do
      cmds = described_class.parse("M 0 0 L 100 100 Z")
      expect(cmds.map(&:type)).to eq(%i[M L Z])
      expect(cmds[0].args).to eq([0.0, 0.0])
      expect(cmds[0].absolute).to be(true)
      expect(cmds[1].args).to eq([100.0, 100.0])
    end

    it "preserves relative flag for lowercase commands" do
      cmds = described_class.parse("m 10 20 l 5 5 z")
      expect(cmds.map(&:absolute)).to eq([false, false, false])
    end

    it "tokenizes compact form without separators" do
      cmds = described_class.parse("M16.5-2.203125")
      expect(cmds[0].type).to eq(:M)
      expect(cmds[0].args).to eq([16.5, -2.203125])
    end

    it "handles scientific notation" do
      cmds = described_class.parse("M 1.5e3 2e-2")
      expect(cmds[0].args).to eq([1500.0, 0.02])
    end

    it "handles comma-separated numbers" do
      cmds = described_class.parse("M 0,0 L 100,100")
      expect(cmds[1].args).to eq([100.0, 100.0])
    end

    it "handles implicit lineto after moveto" do
      cmds = described_class.parse("M 0 0 100 100 200 200")
      expect(cmds.map(&:type)).to eq(%i[M L L])
    end

    it "handles implicit lineto (relative) after lowercase m" do
      cmds = described_class.parse("m 0 0 100 100")
      expect(cmds.map(&:type)).to eq(%i[M L])
      expect(cmds[1].absolute).to be(false)
    end

    it "handles implicit repetition of C" do
      cmds = described_class.parse("C 1 2 3 4 5 6 7 8 9 10 11 12")
      expect(cmds.map(&:type)).to eq(%i[C C])
      expect(cmds[0].args).to eq([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
      expect(cmds[1].args).to eq([7.0, 8.0, 9.0, 10.0, 11.0, 12.0])
    end

    it "handles H and V commands" do
      cmds = described_class.parse("M 0 0 H 100 V 50 Z")
      expect(cmds.map(&:type)).to eq(%i[M H V Z])
    end

    it "handles Q and T commands" do
      cmds = described_class.parse("M 0 0 Q 50 100 100 0 T 200 0")
      expect(cmds.map(&:type)).to eq(%i[M Q T])
    end

    it "handles S (smooth cubic) command" do
      cmds = described_class.parse("M 0 0 C 25 50 75 50 100 0 S 175 -50 200 0")
      expect(cmds.map(&:type)).to eq(%i[M C S])
    end

    it "handles multiple Z commands" do
      cmds = described_class.parse("M 0 0 L 1 1 Z M 2 2 L 3 3 Z")
      expect(cmds.map(&:type)).to eq(%i[M L Z M L Z])
    end

    it "raises a clear error on arc command" do
      expect { described_class.parse("M 0 0 A 50 50 0 0 1 100 0") }
        .to raise_error(ArgumentError, /SVG arc command/)
    end

    it "parses the real ucode R-glyph fixture" do
      fixture_path = "/Users/mulgogi/src/fontist/ucode/tmp/sample_output_17.0.0/blocks/Basic_Latin/U+0052/glyph.svg"
      skip "fixture not available" unless File.exist?(fixture_path)

      fixture = File.read(fixture_path)
      d = fixture.match(/d="([^"]*)"/)&.captures&.first
      skip "no d attribute found" unless d

      cmds = described_class.parse(d)
      expect(cmds.first.type).to eq(:M)
      z_count = cmds.count { |c| c.type == :Z }
      expect(z_count).to eq(3)
      expect(cmds.none? { |c| c.type == :A }).to be(true)
    end
  end
end
