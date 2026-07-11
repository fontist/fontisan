# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe "UFO feature compilation" do
  describe Fontisan::Ufo::Compile::FeatureCompiler do
    describe ".parse" do
      it "extracts ligature substitution rules" do
        fea = <<~FEA
          feature liga {
            sub f i by fi;
            sub f l by fl;
          } liga;
        FEA

        parsed = described_class.parse(fea)
        liga = parsed.ligatures_for("liga")
        expect(liga.size).to eq(2)
        expect(liga[0][:sequence]).to eq(%w[f i])
        expect(liga[0][:result]).to eq("fi")
        expect(liga[1][:sequence]).to eq(%w[f l])
        expect(liga[1][:result]).to eq("fl")
      end

      it "extracts pair positioning rules" do
        fea = <<~FEA
          feature kern {
            pos A V -50;
            pos T o -80;
          } kern;
        FEA

        parsed = described_class.parse(fea)
        pairs = parsed.pairs_for("kern")
        expect(pairs.size).to eq(2)
        expect(pairs[0]).to eq(left: "A", right: "V", value: -50)
        expect(pairs[1]).to eq(left: "T", right: "o", value: -80)
      end

      it "handles multiple feature blocks" do
        fea = <<~FEA
          feature liga {
            sub f i by fi;
          } liga;

          feature dlig {
            sub c t by ct;
          } dlig;
        FEA

        parsed = described_class.parse(fea)
        expect(parsed.ligatures_for("liga").size).to eq(1)
        expect(parsed.ligatures_for("dlig").size).to eq(1)
      end

      it "collects unsupported statements" do
        fea = <<~FEA
          feature liga {
            sub f i by fi;
            chain sub a b by ab;
          } liga;
        FEA

        parsed = described_class.parse(fea)
        expect(parsed.ligatures_for("liga").size).to eq(1)
        expect(parsed.unsupported["liga"]).to include("chain sub a b by ab")
      end

      it "strips comments" do
        fea = <<~FEA
          # This is a comment
          feature liga {
            sub f i by fi; # inline comment
          } liga;
        FEA

        parsed = described_class.parse(fea)
        expect(parsed.ligatures_for("liga").size).to eq(1)
      end

      it "returns empty for blank or nil input" do
        parsed = described_class.parse(nil)
        expect(parsed.empty?).to be true
      end

      it "ignores single-glyph substitutions" do
        fea = <<~FEA
          feature ss01 {
            sub a by a.alt;
          } ss01;
        FEA

        parsed = described_class.parse(fea)
        expect(parsed.ligatures_for("ss01")).to be_empty
        expect(parsed.unsupported["ss01"]).not_to be_empty
      end
    end
  end

  describe Fontisan::Ufo::Compile::Gsub do
    let(:parsed) do
      Fontisan::Ufo::Compile::FeatureCompiler.parse(<<~FEA)
        feature liga {
          sub f i by fi;
          sub f l by fl;
        } liga;
      FEA
    end

    let(:name_to_gid) { { "f" => 10, "i" => 11, "l" => 12, "fi" => 20, "fl" => 21 } }

    describe ".build" do
      it "produces non-empty GSUB bytes for ligature rules" do
        bytes = described_class.build(parsed:, name_to_gid:)
        expect(bytes).to be_a(String)
        expect(bytes).not_to be_empty
      end

      it "returns nil when no ligature rules resolve" do
        empty_parsed = Fontisan::Ufo::Compile::ParsedFeatures.new
        expect(described_class.build(parsed: empty_parsed, name_to_gid:)).to be_nil
      end

      it "starts with version 1.0 header" do
        bytes = described_class.build(parsed:, name_to_gid:)
        version = bytes.unpack1("N")
        expect(version).to eq(0x00010000)
      end
    end
  end
end
