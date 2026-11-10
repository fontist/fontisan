# frozen_string_literal: true

desc "Run the reference corpus benches (ci tier), print the report and write BENCHMARKS.md"
task bench: "corpus:fetch" do
  root = File.expand_path("..", __dir__)
  ok = system(RbConfig.ruby, File.join(root, "benchmark/ci_gate.rb"), "--mode", "report",
              "--write", File.join(root, "BENCHMARKS.md"))
  abort "bench failed" unless ok
end
