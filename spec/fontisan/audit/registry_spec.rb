# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/registry"

RSpec.describe Fontisan::Audit::Registry do
  describe ".each" do
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

  describe "ORDERED_EXTRACTORS" do
    it "is frozen" do
      expect(described_class::ORDERED_EXTRACTORS).to be_frozen
    end

    it "contains no duplicates" do
      expect(described_class::ORDERED_EXTRACTORS.uniq)
        .to eq(described_class::ORDERED_EXTRACTORS)
    end
  end
end
