# frozen_string_literal: true

require_relative "support/corpus_paths"
require_relative "../../scripts/corpus/generate_goldens"

RSpec.describe "read golden determinism" do
  it "generates byte-identical goldens twice" do
    first = CorpusGoldens.generate("ci")
    second = CorpusGoldens.generate("ci")

    expect(second.keys).to eq(first.keys)
    differing = first.keys.reject { |k| first[k].b == second[k].b }
    expect(differing).to eq([])
  end
end
