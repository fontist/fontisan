# frozen_string_literal: true

desc "Run the reference corpus benches (ci tier), print the report and write BENCHMARKS.md"
task :bench do
  root = File.expand_path("..", __dir__)
  abort "corpus/fonts is empty: run `rake corpus:fetch` first" if Dir.glob(File.join(root, "corpus/fonts/*")).empty?

  ok = system(RbConfig.ruby, File.join(root, "benchmark/ci_gate.rb"), "--mode", "report",
              "--write", File.join(root, "BENCHMARKS.md"))
  abort "bench failed" unless ok
end
