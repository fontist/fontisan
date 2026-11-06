#!/usr/bin/env ruby
# frozen_string_literal: true

# Performance gate for the reference corpus benches (fontist/fontisan#157).
#
#   --mode pr      base (--base REF) vs head (--head REF, default HEAD), same
#                  job, interleaved. This is the per-PR check.
#   --mode weekly  head vs the pinned reference commit in benchmark/baseline.json,
#                  same job (ratios, never absolute times). A missing or
#                  unreachable reference fails.
#   --mode tiers   ruby vs native vs ffi (FONTISAN_ENGINE, strict) on the working
#                  tree, same job, interleaved. Hard floor (#160): native must be
#                  at least as fast as ruby on audit_file, audit_dir and scan_dir
#                  and its scan peak RSS must not exceed ruby's (3% tolerance).
#                  Regression gate: native factors must stay within 25% of
#                  benchmark/tier_baseline.json for --platform (default
#                  Gem::Platform.local; no entry = floor only). With --write FILE the
#                  factor table is written into the "Engine tier factors"
#                  section of FILE (BENCHMARKS.md), tagged with --label.
#   --mode report  head only (working tree); prints the report and, with
#                  --write FILE, writes BENCHMARKS.md. Used by `rake bench`.
#
# Each side is a `git archive` copy with its own bundle. Ops the base cannot
# run (e.g. Fontisan::Reference before it exists) are reported "new", not
# compared. Exit 0 pass, 1 regression, 2 error.
#
# FONTISAN_BENCH_SLOWDOWN=2 slows only the head side 2x (gate self-test);
# with FONTISAN_BENCH_SLOWDOWN_TIER=native only the native tier is slowed.

require "json"
require "optparse"
require "etc"
require "time"
require_relative "corpus/harness"
require_relative "corpus/tiers"

module FontisanBench
  # Command line front end.
  class Gate
    ROOT = File.expand_path("..", __dir__)
    HARNESS = File.join(__dir__, "corpus")
    BASELINE = File.join(__dir__, "baseline.json")
    FACTORS_HEADING = "## Engine tier factors"
    FACTORS_SECTION = /^#{FACTORS_HEADING}.*?(?=^## |\z)/m
    FACTORS_TAIL = /^#{FACTORS_HEADING}.*/m

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
        o.on("--label TEXT") { |v| @opts[:label] = v }
        o.on("--platform NAME") { |v| @opts[:platform] = v }
        o.on("--tier-baseline FILE") { |v| @opts[:tier_baseline] = v }
      end.parse!(argv)
    end

    def call
      return report if @opts[:mode] == "report"
      return tiers if @opts[:mode] == "tiers"

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

    def tiers
      sides = Tiers.sides(ROOT)
      args = { harness_dir: HARNESS, corpus: @opts[:corpus] }
      m = Tiers.measure(sides, rounds: @opts[:rounds], **args)
      baseline = tier_baseline
      rows = Tiers.rows(m, baseline: baseline)
      if Tiers.failed?(rows)
        warn "confirming with #{@opts[:rounds]} more rounds"
        Tiers.measure(sides, rounds: @opts[:rounds], into: m, **args)
        rows = Tiers.rows(m, baseline: baseline)
      end
      text = Tiers.markdown(rows, title: "Perf gate: engine tiers (#{@opts[:label] || runner_description})",
                                  rounds: @opts[:rounds])
      puts text
      write_factors(text)
      save(m, [], sides)
      Tiers.failed?(rows) ? 1 : 0
    end

    # The committed expected factors for --platform (default: this Ruby's).
    def tier_baseline
      Tiers.baseline(@opts[:platform] || Gem::Platform.local.to_s,
                     file: @opts[:tier_baseline] || Tiers::BASELINE_FILE)
    end

    def write_factors(text)
      return unless @opts[:write]

      file = @opts[:write]
      body = File.exist?(file) ? File.read(file) : ""
      section = "#{FACTORS_HEADING}\n\n#{factors_section(text)}\n"
      body = body.sub(FACTORS_SECTION, "").rstrip
      File.write(file, "#{body}\n\n#{section}")
    end

    def factors_section(text)
      lines = text.lines.map(&:chomp).drop(1) # drop the "## title" line
      ["- Ruby: #{RUBY_VERSION} (#{RUBY_PLATFORM}); #{@opts[:label] || runner_description}",
       "- fontisan SHA: `#{Side.capture('git', 'rev-parse', 'HEAD', chdir: ROOT).strip}`", *lines].join("\n").rstrip
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
      File.write(@opts[:write], text + kept_factors) if @opts[:write]
      save(m, [], [head])
      0
    end

    # `rake bench` regenerates the file; the tier factor table (written by
    # --mode tiers) is carried over.
    def kept_factors
      return "" unless File.exist?(@opts[:write])

      kept = File.read(@opts[:write])[FACTORS_TAIL]
      kept ? "\n#{kept.rstrip}\n" : ""
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
