# frozen_string_literal: true

# Read goldens (fontist/fontisan#156 card 0b). `corpus:verify` compares only
# and never writes; `corpus:regenerate` rewrites the goldens and is explicit.
namespace :corpus do
  desc "Compare the read goldens with fresh output (TIER=ci|large, default ci); never writes"
  task verify: :fetch do
    require_relative "../scripts/corpus/generate_goldens"
    tier = ENV.fetch("TIER", "ci")
    problems = CorpusGoldens.verify(tier)
    abort "[corpus:verify] #{problems.size} problem(s):\n  #{problems.join("\n  ")}" unless problems.empty?

    puts "[corpus:verify] tier #{tier}: #{CorpusGoldens.entries(tier).size} read goldens match"
  end

  desc "Rewrite the read goldens from the corpus (TIER=ci|large); review the diff"
  task regenerate: :fetch do
    require_relative "../scripts/corpus/generate_goldens"
    tier = ENV.fetch("TIER", "ci")
    puts "[corpus:regenerate] wrote #{CorpusGoldens.write(tier)} goldens (tier #{tier})"
  end
end
