# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit/licensing"

RSpec.describe Fontisan::Models::Audit::Licensing do
  describe "round-trip serialization" do
    let(:attrs) do
      {
        copyright: "© 2024 Example Foundry",
        trademark: "ExampleFont™",
        manufacturer: "Example Foundry",
        designer: "Jane Doe",
        description: "A typeface for examples.",
        vendor_url: "https://example.com",
        designer_url: "https://janedoe.example.com",
        license_description: "SIL Open Font License 1.1",
        license_url: "https://scripts.sil.org/OFL",
        vendor_id: "EXMP",
        embedding_type: "installable",
        fs_selection_flags: %w[regular use_typo_metrics],
      }
    end

    it "round-trips through YAML" do
      model = described_class.new(**attrs)
      parsed = described_class.from_yaml(model.to_yaml)
      expect(parsed.copyright).to eq(attrs[:copyright])
      expect(parsed.embedding_type).to eq("installable")
      expect(parsed.fs_selection_flags).to eq(%w[regular use_typo_metrics])
    end

    it "round-trips through JSON" do
      model = described_class.new(**attrs)
      parsed = described_class.from_json(model.to_json)
      expect(parsed.vendor_id).to eq("EXMP")
      expect(parsed.license_url).to eq(attrs[:license_url])
    end
  end

  describe "with all-nil fields" do
    it "constructs without raising" do
      expect { described_class.new }.not_to raise_error
    end

    it "serializes nil fields cleanly" do
      model = described_class.new
      expect(model.to_hash[:copyright]).to be_nil
    end
  end
end
