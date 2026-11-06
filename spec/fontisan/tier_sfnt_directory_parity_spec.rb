# frozen_string_literal: true

require "spec_helper"

# fontist/fontisan#159: the same malformed sfnt directory fails with the same
# message on every tier, and never with an internal Ruby error text.
RSpec.describe "sfnt directory errors across tiers" do
  include TierParity

  let(:derived) { File.expand_path("../../corpus/derived", __dir__) }
  let(:message) { "Conversion failed: Transformation failed: invalid sfnt table directory" }

  TierParity::TIERS.each do |tier|
    describe "the #{tier} tier" do
      before { skip_unless_built(tier) }

      %w[malformed-truncated-10.ttf malformed-bad-num-tables.ttf malformed-bad-table-offset.ttf
         malformed-truncated-half.ttf].each do |name|
        it "fails convert of #{name} with Fontisan::Error and the stable directory message" do
          result = with_engine(tier) do
            Dir.mktmpdir { |dir| failure { Fontisan.convert(File.join(derived, name), to: :woff, output: File.join(dir, "o.woff")) } }
          end
          expect(result).to eq([Fontisan::Error, message])
        end
      end
    end
  end

  describe Fontisan::SfntDirectory do
    let(:good) { File.binread(File.expand_path("../fixtures/fonttools/TestTTF.ttf", __dir__)) }

    it "accepts a well-formed font" do
      expect { described_class.check!(good) }.not_to raise_error
    end

    it "rejects a table that ends past the end of the file" do
      expect { described_class.check!(good.byteslice(0, good.bytesize - 5)) }
        .to raise_error(described_class::Malformed, described_class::MESSAGE)
    end

    it "rejects a header shorter than twelve bytes" do
      expect { described_class.check!("\x00\x01\x00\x00".b) }.to raise_error(described_class::Malformed, described_class::MESSAGE)
    end
  end
end
