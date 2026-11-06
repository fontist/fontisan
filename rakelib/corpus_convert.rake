# frozen_string_literal: true

require_relative "../scripts/corpus/generate_convert_goldens"

# Convert goldens (card 0c). `corpus:convert:verify` only compares;
# `corpus:convert:regenerate` is the one task that writes. TIER=ci|large|all,
# ONLY=<font-id>[,<font-id>] narrows verify/regenerate. Needs `opentype-sanitizer`
# (OTS_PYTHON=<python with it>) and the pinned woff2_decompress.
module ConvertTasks
  module_function

  def tiers
    Corpus.tiers_for(ENV.fetch("TIER", "ci"))
  end

  def only
    ENV["ONLY"]&.split(",")
  end
end

namespace :corpus do
  namespace :convert do
    desc "Regenerate convert goldens from the reference (TIER, ONLY)"
    task regenerate: "corpus:fetch" do
      files = ConvertGoldens.generate(ConvertTasks.tiers, only: ConvertTasks.only)
      ConvertGoldens.write(files)
      puts "[corpus:convert:regenerate] wrote #{files.size} goldens"
    rescue ConvertGoldens::ToolMissing, Corpus::Error => e
      abort "[corpus:convert:regenerate] #{e.message}"
    end

    desc "Compare regenerated convert output with the committed goldens; never writes (TIER, ONLY)"
    task verify: "corpus:fetch" do
      problems = ConvertGoldens.verify(ConvertTasks.tiers, only: ConvertTasks.only)
      problems.concat(ConvertGoldens.ots_failures.reject { |f| ConvertGoldens.listed_exceptions.include?(f) }
                      .map { |f| "#{f}: OTS failure not listed in corpus/TRIAGE_CONVERT.md" })
      abort "[corpus:convert:verify] #{problems.size} problem(s):\n  #{problems.join("\n  ")}" unless problems.empty?
      puts "[corpus:convert:verify] ok"
    rescue ConvertGoldens::ToolMissing => e
      abort "[corpus:convert:verify] #{e.message}"
    end
  end
end
