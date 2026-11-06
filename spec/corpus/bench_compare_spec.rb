# frozen_string_literal: true

require_relative "../../benchmark/corpus/harness"

# The weekly perf gate compares head with a pinned reference commit. An op
# the reference cannot run has no base number; in weekly (strict) mode that
# must fail instead of passing as "new" (fontist/fontisan#157).
RSpec.describe FontisanBench::Compare do
  let(:measure) do
    instance_double(FontisanBench::Measurement, op_names: %w[audit_file table_parse],
                                                median_rss: nil)
  end

  before do
    allow(measure).to receive(:median_op) do |side, op|
      { %w[base audit_file] => nil, %w[head audit_file] => 0.2,
        %w[base table_parse] => 0.1, %w[head table_parse] => 0.1 }.fetch([side, op])
    end
  end

  it "reports an op without a base as new and passes in pr mode" do
    rows = described_class.rows(measure, tolerance: 0.25)
    expect(rows.find { |r| r.metric == "audit_file" }.status).to eq("new")
    expect(described_class.failed?(rows)).to be(false)
  end

  it "fails an op without a base in strict (weekly) mode" do
    rows = described_class.rows(measure, tolerance: 0.25, strict: true)
    expect(rows.find { |r| r.metric == "audit_file" }.status).to eq("NO-BASE")
    expect(described_class.failed?(rows)).to be(true)
  end
end
