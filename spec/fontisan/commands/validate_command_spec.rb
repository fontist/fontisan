# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::ValidateCommand do
  describe "#run with collection" do
    let(:collection_path) { "spec/fixtures/fonttools/TestTTC.ttc" }

    context "when collection has multiple fonts" do
      it "validates all fonts in the collection" do
        command = described_class.new(input: collection_path)

        # Capture stdout
        output = StringIO.new
        allow($stdout).to receive(:puts).and_wrap_original do |original, *args|
          output.puts(*args) if args.first.is_a?(String)
          original.call(*args)
        end

        command.run

        result = output.string
        expect(result).to include("Collection:")
        expect(result).to include("=== Font 0:")
        expect(result).to include("=== Font 1:")
      end
    end
  end
end
