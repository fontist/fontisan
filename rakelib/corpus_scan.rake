# frozen_string_literal: true

# Scan goldens (fontist/fontisan#156 card 0f). `corpus:scan:verify` compares
# only and never writes; `corpus:scan:regenerate` rewrites and is explicit.
namespace :corpus do
  namespace :scan do
    desc "Compare corpus/goldens/scan with fresh Reference.scan output (TIER=ci|large); never writes"
    task verify: "corpus:fetch" do
      require_relative "../scripts/corpus/generate_scan_goldens"
      tier = ENV.fetch("TIER", "ci")
      problems = ScanGoldens.verify(tier)
      abort "[corpus:scan:verify] #{problems.size} problem(s):\n  #{problems.join("\n  ")}" unless problems.empty?

      puts "[corpus:scan:verify] tier #{tier}: #{ScanGoldens.entries(tier).size} scan goldens match"
    end

    desc "Rewrite the scan goldens (TIER=ci|large); review the diff"
    task regenerate: "corpus:fetch" do
      require_relative "../scripts/corpus/generate_scan_goldens"
      tier = ENV.fetch("TIER", "ci")
      puts "[corpus:scan:regenerate] wrote #{ScanGoldens.write(tier)} goldens (tier #{tier})"
    end
  end
end
