# frozen_string_literal: true

# Runs every benchmark op once-per-process-style and prints JSON:
#   {"ops": {"name": seconds_per_call | null}, "scan_peak_rss_kb": n | null, ...}
#
# Usage: ruby -I<fontisan>/lib benchmark/corpus/run.rb --corpus DIR [--side head|base]
#
# The harness lives in the checkout that invokes it; the fontisan under test
# is whatever `require "fontisan"` resolves to (-I or BUNDLE_GEMFILE).
#
# FONTISAN_BENCH_SLOWDOWN=2 makes the `head` side run each op N times slower
# (it sleeps (N-1) x the op's own time), to prove the gate goes red.

require "json"
require "optparse"
require "rbconfig"
require "benchmark"
require_relative "ops"

module FontisanBench
  # Times ops and measures the peak RSS of the directory scan.
  class Runner
    MIN_SECONDS = 0.25
    MIN_REPS = 3
    SLOW_SECONDS = 2.0
    MAX_REPS = 200

    def initialize(corpus:, side:, only: nil)
      @ops = Ops.new(corpus)
      @side = side
      @only = only
      @slowdown = slowdown_for(side)
    end

    def call
      ops = {}
      @ops.all.each do |op|
        next if @only && !@only.include?(op.name)

        ops[op.name] = runnable?(op) ? time(op) : nil
      end
      { "ops" => ops, "scan_peak_rss_kb" => scan_rss, "ruby" => RUBY_VERSION,
        "fontisan_version" => (defined?(Fontisan::VERSION) ? Fontisan::VERSION : nil) }
    end

    private

    # FONTISAN_BENCH_SLOWDOWN_TIER=native limits the forced slowdown to the
    # run whose FONTISAN_ENGINE is that tier (the tiers gate self-test).
    def slowdown_for(side)
      return 1.0 unless side == "head"

      tier = ENV.fetch("FONTISAN_BENCH_SLOWDOWN_TIER", "")
      return 1.0 unless tier.empty? || tier == ENV.fetch("FONTISAN_ENGINE", "")

      ENV.fetch("FONTISAN_BENCH_SLOWDOWN", "1").to_f
    end

    def runnable?(bench)
      bench.requires.all? { |const| Object.const_defined?(const) }
    end

    # Fastest call in seconds after one untimed warm-up call. Calls repeat
    # until MIN_SECONDS of measured time and at least MIN_REPS calls (unless
    # the op is already slow), and the minimum is reported: it is the figure
    # least disturbed by other load on a shared runner.
    def time(bench)
      bench.body.call
      times = []
      while times.size < MAX_REPS && keep_timing?(times)
        one = Benchmark.realtime { bench.body.call }
        # forced slowdown: sleep (N-1) x the call's own time, counted as run time
        times << one + (@slowdown > 1 ? slow_sleep(one) : 0)
      end
      times.min
    end

    def keep_timing?(times)
      total = times.sum
      times.empty? || total < MIN_SECONDS || (times.size < MIN_REPS && total < SLOW_SECONDS)
    end

    def slow_sleep(one)
      extra = one * (@slowdown - 1)
      sleep(extra)
      extra
    end

    def scan_rss
      return nil unless Object.const_defined?("Fontisan::Reference")
      return nil if @only && !@only.include?("scan_dir")

      lib = File.dirname($LOADED_FEATURES.grep(%r{/fontisan\.rb\z}).first.to_s)
      Rss.peak_kb(
        [RbConfig.ruby, "-I", lib, File.join(__dir__, "scan_child.rb"), @ops.corpus],
        env: ENV.to_h,
      )
    end
  end

  # Peak resident set size of a child process: time(1) on macOS and Linux,
  # a PowerShell sampler of PeakWorkingSet64 on Windows. nil when the
  # platform cannot measure it; the tiers gate then skips only the RSS check.
  module Rss
    WINDOWS = /mswin|mingw|cygwin/
    # Polls the child's peak working set until it exits (the value is gone
    # once the process object is released, so it is sampled, never read late).
    POWERSHELL = <<~PS
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $env:FONTISAN_RSS_EXE
      $psi.Arguments = $env:FONTISAN_RSS_ARGS
      $psi.UseShellExecute = $false
      $p = [System.Diagnostics.Process]::Start($psi)
      $peak = 0
      while (-not $p.HasExited) {
        try { $p.Refresh(); if ($p.PeakWorkingSet64 -gt $peak) { $peak = $p.PeakWorkingSet64 } } catch {}
        Start-Sleep -Milliseconds 5
      }
      $p.WaitForExit()
      if ($p.ExitCode -ne 0) { exit 1 }
      Write-Output ("PEAK_BYTES=" + $peak)
    PS

    module_function

    def supported?
      windows? || (File.executable?("/usr/bin/time") && !RbConfig::CONFIG["host_os"].match?(WINDOWS))
    end

    def windows?
      RbConfig::CONFIG["host_os"].match?(WINDOWS)
    end

    def peak_kb(cmd, env: {})
      require "open3"
      return windows_peak_kb(cmd, env) if windows?

      flag = RbConfig::CONFIG["host_os"].include?("darwin") ? "-l" : "-v"
      return nil unless File.executable?("/usr/bin/time")

      _out, err, status = Open3.capture3(env, "/usr/bin/time", flag, *cmd)
      return nil unless status.success?

      parse(err, flag)
    end

    def windows_peak_kb(cmd, env)
      args = cmd.drop(1).map { |a| %("#{a}") }.join(" ")
      out, _err, status = Open3.capture3(env.merge("FONTISAN_RSS_EXE" => cmd.first, "FONTISAN_RSS_ARGS" => args),
                                         "powershell", "-NoProfile", "-NonInteractive", "-Command", POWERSHELL)
      return nil unless status.success?

      m = out.match(/PEAK_BYTES=(\d+)/)
      m && m[1].to_i.positive? ? m[1].to_i / 1024 : nil
    rescue SystemCallError
      nil
    end

    def parse(text, flag)
      if flag == "-l" # macOS: bytes
        m = text.match(/^\s*(\d+)\s+maximum resident set size/)
        m && (m[1].to_i / 1024)
      else # Linux: kbytes
        m = text.match(/Maximum resident set size \(kbytes\): (\d+)/)
        m && m[1].to_i
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  opts = { side: "head", corpus: nil, only: nil }
  OptionParser.new do |o|
    o.on("--corpus DIR") { |v| opts[:corpus] = v }
    o.on("--side SIDE") { |v| opts[:side] = v }
    o.on("--only LIST") { |v| opts[:only] = v.split(",") }
  end.parse!
  abort "--corpus DIR is required" unless opts[:corpus]

  require "fontisan"
  puts JSON.generate(FontisanBench::Runner.new(**opts).call)
end
