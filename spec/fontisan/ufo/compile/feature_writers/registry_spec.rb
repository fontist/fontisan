# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/feature_writers"

RSpec.describe Fontisan::Ufo::Compile::FeatureWriters do
  describe "DEFAULT_WRITERS" do
    it "includes Gdef, Kern, Mark, Mkmk, Curs" do
      expect(described_class::DEFAULT_WRITERS).to eq([
                                                       described_class::Gdef,
                                                       described_class::Kern,
                                                       described_class::Mark,
                                                       described_class::Mkmk,
                                                       described_class::Curs,
                                                     ])
    end

    it "is frozen" do
      expect(described_class::DEFAULT_WRITERS).to be_frozen
    end
  end
end
