# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff"

RSpec.describe Fontisan::Tables::Cff::Cff2CharStringBuilder do
  describe "operator table" do
    it "removes hmoveto (replaced by vsindex in CFF2)" do
      expect(described_class::OPERATORS_CFF2).not_to have_key(:hmoveto)
    end

    it "adds vsindex (22)" do
      expect(described_class::OPERATORS_CFF2[:vsindex]).to eq(22)
    end

    it "adds blend (23)" do
      expect(described_class::OPERATORS_CFF2[:blend]).to eq(23)
    end

    it "preserves endchar (14)" do
      expect(described_class::OPERATORS_CFF2[:endchar]).to eq(14)
    end
  end
end
