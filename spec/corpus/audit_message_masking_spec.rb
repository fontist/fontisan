# frozen_string_literal: true

require_relative "support/corpus_paths"

RSpec.describe "Reference.audit messages" do
  it "carry no object address, so two runs give identical text" do
    path = CorpusPaths.path("fonttools-test-woff")
    messages = Fontisan::Reference.audit(path, validate: true).first["validation_issues"]
      .map { |i| i["message"] }

    expect(messages.grep(/failed to execute/)).not_to be_empty
    expect(messages.join).not_to match(/0x\h{6,}/)
    expect(messages.join).to include("for #<Fontisan::WoffHeader>")
  end
end
