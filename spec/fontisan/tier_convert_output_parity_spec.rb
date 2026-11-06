# frozen_string_literal: true

require "spec_helper"

# fontist/fontisan#159: Fontisan.convert prints nothing and records its tier on
# every tier. The Ruby tier used to print progress and record no served_by.
RSpec.describe "Fontisan.convert output across tiers" do
  include TierParity

  let(:ttf) { File.expand_path("../fixtures/fonttools/TestTTF.ttf", __dir__) }

  TierParity::TIERS.each do |tier|
    it "is quiet and records #{tier} as the serving tier" do
      skip_unless_built(tier)
      Dir.mktmpdir do |dir|
        with_engine(tier) do
          expect { Fontisan.convert(ttf, to: :woff, output: File.join(dir, "o.woff")) }
            .not_to output.to_stdout
          expect(Fontisan::Engine.served_by(:convert)).to eq(tier.to_sym)
        end
      end
    end

    it "returns the same result keys on the #{tier} tier" do
      skip_unless_built(tier)
      Dir.mktmpdir do |dir|
        result = with_engine(tier) { Fontisan.convert(ttf, to: :woff, output: File.join(dir, "o.woff")) }
        expect(result).to include(success: true, source_format: :ttf, target_format: :woff)
      end
    end
  end
end
