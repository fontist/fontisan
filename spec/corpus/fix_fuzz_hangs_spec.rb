# frozen_string_literal: true

require "open3"
require "rbconfig"
require "timeout"
require_relative "support/corpus_paths"

# Reference.read in full mode used to run for minutes on these fuzz-found
# inputs (an unbounded cmap format 12 span and a CFF2 INDEX count of 2**32-1).
# Each read runs in a child process so a regression fails fast instead of
# hanging the suite.
RSpec.describe "Reference.read on fuzz-found malformed fonts" do
  let(:lib) { File.expand_path("../../lib", __dir__) }

  def read_in_child(lib, path, limit)
    script = 'require "fontisan"; begin; Fontisan::Reference.read(ARGV[0], mode: :full); ' \
             'rescue StandardError; end; print "done"'
    Open3.popen3(RbConfig.ruby, "-I#{lib}", "-e", script, path) do |_in, out, _err, thread|
      Timeout.timeout(limit) { thread.value }
      out.read
    rescue Timeout::Error
      Process.kill("KILL", thread.pid)
      "timeout"
    end
  end

  %w[malformed-fuzz-cmap12-u32-span.ttf malformed-fuzz-cff2-huge-count.otf].each do |name|
    it "finishes #{name} within 15 seconds" do
      path = File.join(CorpusPaths::ROOT, "corpus", "derived", name)
      expect(read_in_child(lib, path, 15)).to eq("done")
    end
  end
end
