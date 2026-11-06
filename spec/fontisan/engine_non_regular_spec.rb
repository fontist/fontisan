# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "rbrace" if false # rubocop:disable Lint/LiteralAsCondition
require "rbconfig"

# A FIFO, device or socket must never reach the native or ffi engine: their
# read runs with the GVL released, so SIGTERM, Timeout and Ctrl-C cannot
# interrupt it (#159 break-test F1). Ruby's own read is interruptible, so the
# Ruby tier serves such a path. The probe runs in a child process that is
# SIGKILLed on a deadline, so a regression fails the example instead of
# hanging the suite.
RSpec.describe "engine routing of non-regular files" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:ttf) { File.join(root, "spec/fixtures/fonttools/TestTTF.ttf") }
  let(:script) do
    <<~RUBY
      require "fontisan"
      path = ARGV.fetch(0)
      ops = %i[read audit scan convert extract instance subset]
      puts ops.map { |op| "\#{op}=\#{Fontisan::Engine.resolve(op, path)}" }.join(",")
    RUBY
  end

  def resolve_in_child(tier, path, deadline: 20)
    out, wr = IO.pipe
    pid = Process.spawn({ "FONTISAN_ENGINE" => tier, "FONTISAN_ENGINE_STRICT" => nil },
                        RbConfig.ruby, "-I#{root}/lib", "-e", script, path,
                        out: wr, err: File::NULL, chdir: root)
    wr.close
    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline
    status = nil
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < finish
      status = Process.wait2(pid, Process::WNOHANG)&.last
      break if status

      sleep 0.05
    end
    unless status
      Process.kill("KILL", pid)
      Process.wait(pid)
      return :hung
    end
    out.read.strip
  ensure
    out&.close
  end

  { "native" => Fontisan::Native, "ffi" => Fontisan::Ffi }.each do |tier, mod|
    context "with FONTISAN_ENGINE=#{tier}" do
      before do
        skip "#{tier} tier not built" unless mod.available?
      end

      it "routes a FIFO to the Ruby tier for every operation, without blocking" do
        Dir.mktmpdir do |dir|
          fifo = File.join(dir, "pipe.ttf")
          File.mkfifo(fifo)
          expect(resolve_in_child(tier, fifo))
            .to eq(%w[read audit scan convert extract instance subset].map { |op| "#{op}=ruby" }.join(","))
        end
      end

      it "still serves a regular font" do
        expect(resolve_in_child(tier, ttf)).to include("read=#{tier}", "audit=#{tier}")
      end
    end
  end
end
