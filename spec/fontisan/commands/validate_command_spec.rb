# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::ValidateCommand do
  describe "#run with collection" do
    let(:collection_path) { "/System/Library/Fonts/LucidaGrande.ttc" }

    context "when collection has multiple fonts" do
      it "validates all fonts in the collection", skip: "Requires system font, manual verification" do
        command = described_class.new(input: collection_path)

        # Capture output
        output = capture_stdout { command.run }

        expect(output).to include("Collection:")
        expect(output).to include("=== Font 0:")
        expect(output).to include("=== Font 1:")
      end
    end
  end
end
