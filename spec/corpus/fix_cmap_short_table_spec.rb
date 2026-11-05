# frozen_string_literal: true

require_relative "support/corpus_paths"

RSpec.describe "cmap check on a short table" do
  def issues(id)
    Fontisan::Reference.audit(CorpusPaths.path(id), validate: true).first.fetch("validation_issues")
  end

  it "reports an empty cmap table as an issue instead of failing the check" do
    messages = issues("quirk-empty-cmap-table").map { |i| i["message"] }

    expect(messages.grep(/failed to execute/)).to be_empty
    expect(messages).to include(a_string_matching(/cmap table is 0 bytes/))
  end
end
