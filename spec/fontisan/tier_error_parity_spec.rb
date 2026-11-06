# frozen_string_literal: true

require "spec_helper"

# fontist/fontisan#159: a bad font fails with the same class and message on
# every tier, so `rescue Fontisan::InvalidFontError` does not depend on which
# tier happened to serve the call.
RSpec.describe "error parity across tiers" do
  include TierParity

  let(:derived) { File.expand_path("../../corpus/derived", __dir__) }

  def convert_failure(file)
    Dir.mktmpdir { |dir| failure { Fontisan.convert(file, to: :woff, output: File.join(dir, "o.woff")) } }
  end

  TierParity::TIERS.each do |tier|
    describe "the #{tier} tier" do
      before { skip_unless_built(tier) }

      %w[malformed-empty.ttf malformed-garbage.ttf].each do |name|
        it "fails convert of #{name} with InvalidFontError and the loader's message" do
          result = with_engine(tier) { convert_failure(File.join(derived, name)) }
          expect(result).to eq([Fontisan::InvalidFontError, Fontisan::FontLoader::UNKNOWN_FORMAT_MESSAGE])
        end

        it "fails subset of #{name} the same way" do
          result = with_engine(tier) { failure { Fontisan::Reference.subset(File.join(derived, name), text: "a") } }
          expect(result).to eq([Fontisan::InvalidFontError, Fontisan::FontLoader::UNKNOWN_FORMAT_MESSAGE])
        end
      end

      it "fails subset of a truncated font with the Ruby tier's class and an unwrapped message" do
        file = File.join(derived, "malformed-truncated-10.ttf")
        result = with_engine(tier) { failure { Fontisan::Reference.subset(file, text: "a") } }
        expect(result).to eq([RuntimeError, "Invalid TrueTypeFont file: End of file reached"])
      end
    end
  end
end
