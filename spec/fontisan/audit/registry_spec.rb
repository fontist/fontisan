# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/registry"

RSpec.describe Fontisan::Audit::Registry do
  describe ".each (default mode)" do
    it "yields every registered extractor class" do
      yielded = []
      described_class.each { |cls| yielded << cls }

      expect(yielded).to include(Fontisan::Audit::Extractors::Provenance)
      expect(yielded).to include(Fontisan::Audit::Extractors::Identity)
      expect(yielded).to include(Fontisan::Audit::Extractors::Style)
      expect(yielded).to include(Fontisan::Audit::Extractors::Coverage)
      expect(yielded).to include(Fontisan::Audit::Extractors::Aggregations)
    end

    it "yields Provenance before Aggregations (deterministic order)" do
      yielded = []
      described_class.each { |cls| yielded << cls }

      prov_idx = yielded.index(Fontisan::Audit::Extractors::Provenance)
      agg_idx = yielded.index(Fontisan::Audit::Extractors::Aggregations)
      expect(prov_idx).to be < agg_idx
    end
  end

  describe ".each with mode: :brief" do
    it "yields only the brief-subset extractors" do
      yielded = []
      described_class.each(mode: :brief) { |cls| yielded << cls }

      expect(yielded).to include(Fontisan::Audit::Extractors::Provenance)
      expect(yielded).to include(Fontisan::Audit::Extractors::Identity)
      expect(yielded).to include(Fontisan::Audit::Extractors::Style)
      expect(yielded).to include(Fontisan::Audit::Extractors::Licensing)
      expect(yielded).to include(Fontisan::Audit::Extractors::Coverage)
    end

    it "omits expensive extractors in brief mode" do
      yielded = []
      described_class.each(mode: :brief) { |cls| yielded << cls }

      expect(yielded).not_to include(Fontisan::Audit::Extractors::Metrics)
      expect(yielded).not_to include(Fontisan::Audit::Extractors::Hinting)
      expect(yielded).not_to include(Fontisan::Audit::Extractors::Aggregations)
      expect(yielded).not_to include(Fontisan::Audit::Extractors::LanguageCoverage)
    end
  end

  describe ".extractors_for" do
    it "returns BRIEF_EXTRACTORS for :brief" do
      expect(described_class.extractors_for(:brief))
        .to eq(described_class::BRIEF_EXTRACTORS)
    end

    it "returns ORDERED_EXTRACTORS for :full (default)" do
      expect(described_class.extractors_for(:full))
        .to eq(described_class::ORDERED_EXTRACTORS)
    end

    it "falls back to ORDERED_EXTRACTORS for unknown modes" do
      expect(described_class.extractors_for(:unknown))
        .to eq(described_class::ORDERED_EXTRACTORS)
    end
  end

  describe "ORDERED_EXTRACTORS" do
    it "is frozen" do
      expect(described_class::ORDERED_EXTRACTORS).to be_frozen
    end

    it "contains no duplicates" do
      expect(described_class::ORDERED_EXTRACTORS.uniq)
        .to eq(described_class::ORDERED_EXTRACTORS)
    end
  end

  describe "BRIEF_EXTRACTORS" do
    it "is frozen" do
      expect(described_class::BRIEF_EXTRACTORS).to be_frozen
    end

    it "contains no duplicates" do
      expect(described_class::BRIEF_EXTRACTORS.uniq)
        .to eq(described_class::BRIEF_EXTRACTORS)
    end

    it "is a strict subset of ORDERED_EXTRACTORS" do
      expect(described_class::ORDERED_EXTRACTORS)
        .to include(*described_class::BRIEF_EXTRACTORS)
    end
  end
end
