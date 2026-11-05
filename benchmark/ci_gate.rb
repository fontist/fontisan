#!/usr/bin/env ruby
# frozen_string_literal: true

# Performance gate for the reference corpus benches (fontist/fontisan#157).
#
#   --mode pr      base (--base REF) vs head (--head REF, default HEAD), same
#                  job, interleaved. This is the per-PR check.
#   --mode weekly  head vs the pinned reference commit in benchmark/baseline.json,
#                  same job (ratios, never absolute times). A missing or
#                  unreachable reference fails.
#   --mode report  head only (working tree); prints the report and, with
#                  --write FILE, writes BENCHMARKS.md. Used by `rake bench`.
#
# Each side is a `git archive` copy with its own bundle. Ops the base cannot
# run (e.g. Fontisan::Reference before it exists) are reported "new", not
# compared. Exit 0 pass, 1 regression, 2 error.
#
# FONTISAN_BENCH_SLOWDOWN=2 slows only the head side 2x (gate self-test).

require "json"
require "optparse"
require "etc"
require "time"
require_relative "corpus/harness"

module FontisanBench
  # Command line front end.
  class Gate
    ROOT = File.expand_path("..", __dir__)
    HARNESS = File.join(__dir__, "corpus")
    BASELINE = File.join(__dir__, "baseline.json")

    def initialize(argv)
      @opts = { mode: "pr", head: "HEAD", rounds: 5, tolerance: 0.25,
                corpus: File.join(ROOT, "corpus") }
      OptionParser.new do |o|
        o.on("--mode MODE") { |v| @opts[:mode] = v }
        o.on("--base REF") { |v| @opts[:base] = v }
        o.on("--head REF") { |v| @opts[:head] = v }
        o.on("--rounds N", Integer) { |v| @opts[:rounds] = v }
        o.on("--tolerance F", Float) { |v| @opts[:tolerance] = v }
        o.on("--corpus DIR") { |v| @opts[:corpus] = v }
        o.on("--baseline FILE") { |v| @opts[:baseline] = v }
        o.on("--save FILE") { |v| @opts[:save] = v }
        o.on("--write FILE") { |v| @opts[:write] = v }
      end.parse!(argv)
    end

    def call
      return report if @opts[:mode] == "report"

      Dir.mktmpdir("fontisan-gate") { |work| compare(work) }
    rescue Error => e
      warn "ERROR: #{e.message}"
      2
    end

    private

    def compare(work)
      base_ref = @opts[:mode] == "weekly" ? reference_commit : @opts[:base]
      raise Error, "--base REF is required for --mode pr" unless base_ref

      sides = [Side.from_ref("base", base_ref, root: ROOT, workdir: work),
               Side.from_ref("head", @opts[:head], root: ROOT, workdir: work)]
      m = Measurement.interleave(sides, rounds: @opts[:rounds], harness_dir: HARNESS, corpus: @opts[:corpus])
      rows = Compare.rows(m, tolerance: @opts[:tolerance])
      rows = confirm(m, sides, rows)
      title = @opts[:mode] == "weekly" ? "Perf gate: head vs pinned reference" : "Perf gate: head vs base"
      puts Compare.markdown(rows, title: "#{title} (#{sides[0].ref[0, 8]} -> #{sides[1].ref[0, 8]})",
                                  tolerance: @opts[:tolerance], rounds: @opts[:rounds])
      save(m, rows, sides)
      Compare.failed?(rows) ? 1 : 0
    end

    # A shared runner is noisy: ops that look regressed are re-measured in
    # the same job (more interleaved rounds, medians over all rounds) and only
    # fail if they still regress.
    def confirm(measure, sides, rows)
      suspects = rows.select { |r| r.status == "REGRESSION" }.map(&:metric)
      return rows if suspects.empty?

      ops = suspects - ["scan_peak_rss_kb"]
      ops = ["scan_dir"] if ops.empty?
      warn "confirming #{suspects.join(', ')} with #{@opts[:rounds]} more rounds"
      Measurement.interleave(sides, rounds: @opts[:rounds], harness_dir: HARNESS,
                                    corpus: @opts[:corpus], only: ops, into: measure)
      Compare.rows(measure, tolerance: @opts[:tolerance])
    end

    def reference_commit
      file = @opts[:baseline] || BASELINE
      raise Error, "reference baseline #{file} is missing" unless File.exist?(file)

      ref = JSON.parse(File.read(file))["reference_commit"].to_s
      raise Error, "#{file} has no reference_commit" if ref.empty?

      ref
    end

    def report
      head = Side.new("head", ROOT, ref: Side.capture("git", "rev-parse", "HEAD", chdir: ROOT).strip)
      m = Measurement.interleave([head], rounds: @opts[:rounds], harness_dir: HARNESS, corpus: @opts[:corpus])
      text = report_markdown(m, head)
      puts text
      File.write(@opts[:write], text) if @opts[:write]
      save(m, [], [head])
      0
    end

    def report_markdown(measure, head)
      dirty = Side.capture("git", "status", "--porcelain", "--", "lib", chdir: ROOT).strip.empty? ? "" : "+dirty"
      lines = ["# Benchmarks", "",
               "Reference corpus `ci` tier benches for the #157 operations (`rake bench`).", "",
               "- fontisan SHA: `#{head.ref}#{dirty}`",
               "- Ruby: #{RUBY_VERSION} (#{RUBY_PLATFORM})",
               "- Runner: #{runner_description}",
               "- Rounds: #{@opts[:rounds]} (median per op); each op is the fastest of repeated calls " \
               "(at least 3 calls or 0.25 s of measured time)", "",
               "| operation | median |", "|---|---|"]
      measure.op_names.each { |op| lines << "| #{op} | #{Compare.fmt(op, measure.median_op('head', op))} |" }
      lines << "| scan_peak_rss (directory scan) | #{Compare.fmt('scan_peak_rss_kb', measure.median_rss('head'))} |"
      "#{lines.join("\n")}\n"
    end

    def runner_description
      cpu = if RUBY_PLATFORM.include?("darwin")
              Side.capture("sysctl", "-n", "machdep.cpu.brand_string").strip
            else
              File.foreach("/proc/cpuinfo").grep(/model name/).first.to_s.split(":", 2).last.to_s.strip
            end
      "#{ENV.fetch('RUNNER_OS', RbConfig::CONFIG['host_os'])}, #{cpu}, #{Etc.nprocessors} cores"
    rescue StandardError
      RbConfig::CONFIG["host_os"]
    end

    def save(measure, rows, sides)
      return unless @opts[:save]

      data = { "sides" => sides.to_h { |s| [s.name, s.ref] }, "runs" => measure.runs,
               "rows" => rows.map(&:to_h) }
      File.write(@opts[:save], JSON.pretty_generate(data))
    end
  end
end

exit FontisanBench::Gate.new(ARGV).call if $PROGRAM_NAME == __FILE__
