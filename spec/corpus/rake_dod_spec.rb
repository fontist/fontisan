# frozen_string_literal: true

require "open3"
require "rbconfig"

# Definition of done for fontist/fontisan#157: on a fresh clone (no
# corpus/fonts), `rake corpus:verify` and `rake bench` must both fetch the
# corpus themselves rather than abort or need a manual step.
RSpec.describe "corpus Rake tasks on a fresh clone" do # rubocop:disable RSpec/DescribeClass
  let(:graph) do
    root = File.expand_path("../..", __dir__)
    out, = Open3.capture2(RbConfig.ruby, "-S", "rake", "-P", chdir: root)
    out.scan(/^rake (\S+)\n((?:    \S+\n)*)/).to_h { |n, deps| [n, deps.split.map(&:strip)] }
  end

  # `rake -P` prints a prerequisite relative to its namespace, so inside
  # corpus: the fetch task shows as "fetch".
  { "corpus:verify" => "fetch", "bench" => "corpus:fetch" }.each do |name, dep|
    it "#{name} depends on corpus:fetch" do
      expect(graph.fetch(name)).to include(dep)
    end
  end
end
