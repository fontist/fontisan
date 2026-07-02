# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff2"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Tables::Cff::Cff2CharStringBuilder do
  describe "operator differences from CFF1" do
    it "replaces hmoveto (22) with vsindex" do
      expect(described_class::OPERATORS_CFF2[:hmoveto]).to be_nil
      expect(described_class::OPERATORS_CFF2[:vsindex]).to eq(22)
    end

    it "adds blend operator (23)" do
      expect(described_class::OPERATORS_CFF2[:blend]).to eq(23)
    end
  end
end
