# frozen_string_literal: true

# Malformed-input goldens (fontist/fontisan#156, card 0e).
namespace :corpus do
  namespace :malformed do
    desc "Check corpus/goldens/malformed against current Ruby behaviour"
    task :verify do
      require_relative "../scripts/corpus/generate_malformed_goldens"
      problems = MalformedGoldens.verify
      abort "[corpus:malformed:verify]\n  #{problems.join("\n  ")}" unless problems.empty?
      puts "[corpus:malformed:verify] ok (#{MalformedGoldens.entries.size} kinds)"
    end

    desc "Regenerate corpus/goldens/malformed (only in a PR that shows the golden diff)"
    task :regenerate do
      require_relative "../scripts/corpus/generate_malformed_goldens"
      puts "[corpus:malformed:regenerate] wrote #{MalformedGoldens.regenerate} goldens"
    end
  end
end
