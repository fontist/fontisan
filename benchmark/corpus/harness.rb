# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

module FontisanBench
  class Error < StandardError; end

  # One copy of fontisan to measure, with its own bundle.
  class Side
    attr_reader :name, :dir, :ref

    # @param name [String] "base" or "head"
    # @param dir [String] checkout directory (own Gemfile)
    def initialize(name, dir, ref: nil)
      @name = name
      @dir = dir
      @ref = ref
    end

    # `git archive REF` into a fresh directory with its own bundle. A git
    # archive has no .git, so the gemspec lists no files but still loads, and
    # nothing here relies on exe/.
    def self.from_ref(name, ref, root:, workdir:)
      sha = capture("git", "rev-parse", "--verify", "#{ref}^{commit}", chdir: root).strip
      dir = File.join(workdir, name)
      FileUtils.mkdir_p(dir)
      archive = File.join(workdir, "#{name}.tar")
      run!("git", "archive", "--format=tar", "-o", archive, sha, chdir: root)
      run!("tar", "-xf", archive, "-C", dir)
      lock = File.join(root, "Gemfile.lock")
      FileUtils.cp(lock, dir) if File.exist?(lock)
      side = new(name, dir, ref: sha)
      side.bundle_install
      side
    end

    def self.capture(*cmd, chdir: nil)
      out, err, st = Open3.capture3(*cmd, chdir: chdir || Dir.pwd)
      raise Error, "#{cmd.join(' ')} failed: #{err}" unless st.success?

      out
    end

    def self.run!(*cmd, chdir: nil, env: {})
      out, st = Open3.capture2e(env, *cmd, chdir: chdir || Dir.pwd)
      raise Error, "#{cmd.join(' ')} failed:\n#{out}" unless st.success?

      out
    end

    def env
      { "BUNDLE_GEMFILE" => File.join(dir, "Gemfile"), "BUNDLE_FROZEN" => "false",
        "BUNDLE_DEPLOYMENT" => "false" }
    end

    def bundle_install
      self.class.run!("bundle", "install", "--quiet", env: env, chdir: dir)
    end

    # One process: every op once-per-calibration, JSON result.
    def run_once(harness_dir, corpus, only: nil)
      cmd = ["bundle", "exec", RbConfig.ruby, File.join(harness_dir, "run.rb"),
             "--corpus", corpus, "--side", name]
      cmd += ["--only", only.join(",")] if only
      out, err, st = Open3.capture3(env, *cmd, chdir: dir)
      raise Error, "bench run on #{name} failed:\n#{err}" unless st.success?

      JSON.parse(out.lines.reverse_each.find { |l| l.start_with?("{") })
    end
  end

  # Interleaved rounds over two (or one) sides, median per metric.
  class Measurement
    METRICS_RSS = "scan_peak_rss_kb"

    attr_reader :runs

    def initialize
      @runs = Hash.new { |h, k| h[k] = [] }
    end

    def record(side_name, result)
      @runs[side_name] << result
    end

    def op_names
      @runs.values.flatten.flat_map { |r| r["ops"].keys }.uniq
    end

    def median_op(side, name)
      median(@runs[side].map { |r| r["ops"][name] })
    end

    def median_rss(side)
      median(@runs[side].map { |r| r[METRICS_RSS] })
    end

    def median(values)
      v = values.compact.sort
      return nil if v.empty?

      mid = v.size / 2
      v.size.odd? ? v[mid] : (v[mid - 1] + v[mid]) / 2.0
    end

    # Round i runs the sides in alternating order, so drift (thermal, noisy
    # neighbours) hits both sides alike.
    def self.interleave(sides, rounds:, harness_dir:, corpus:, log: $stderr, only: nil, into: nil)
      m = into || new
      rounds.times do |i|
        order = i.even? ? sides : sides.reverse
        order.each do |side|
          log.puts "round #{i + 1}/#{rounds}: #{side.name}"
          m.record(side.name, side.run_once(harness_dir, corpus, only: only))
        end
      end
      m
    end
  end

  # base vs head verdicts.
  module Compare
    Row = Struct.new(:metric, :base, :head, :ratio, :status, keyword_init: true)

    module_function

    # `strict` (weekly mode): the pinned reference must be able to run every
    # op, so an op with no base number is "NO-BASE" and fails instead of "new".
    def rows(measure, tolerance:, strict: false)
      ops = measure.op_names.map do |op|
        row(op, measure.median_op("base", op), measure.median_op("head", op), tolerance, strict: strict)
      end
      ops << row("scan_peak_rss_kb", measure.median_rss("base"), measure.median_rss("head"), tolerance, strict: strict)
      ops
    end

    def row(metric, base, head, tolerance, strict: false)
      return Row.new(metric: metric, base: base, head: head, status: "n/a") if head.nil? && base.nil?
      return Row.new(metric: metric, base: base, head: head, status: "MISSING-ON-HEAD") if head.nil?
      return Row.new(metric: metric, base: base, head: head, status: strict ? "NO-BASE" : "new") if base.nil?

      ratio = head.to_f / base
      Row.new(metric: metric, base: base, head: head, ratio: ratio,
              status: ratio > 1 + tolerance ? "REGRESSION" : "ok")
    end

    def failed?(rows)
      rows.any? { |r| %w[REGRESSION MISSING-ON-HEAD NO-BASE].include?(r.status) }
    end

    def markdown(rows, title:, tolerance:, rounds:)
      out = ["## #{title}", "",
             "Median of #{rounds} interleaved rounds; fails when head is more than " \
             "#{(tolerance * 100).round}% slower than base.", "",
             "| metric | base | head | head/base | status |", "|---|---|---|---|---|"]
      rows.each do |r|
        out << "| #{r.metric} | #{fmt(r.metric, r.base)} | #{fmt(r.metric, r.head)} | " \
               "#{r.ratio ? format('%.2fx', r.ratio) : '-'} | #{r.status} |"
      end
      out << ""
      out << (failed?(rows) ? "**RESULT: FAIL**" : "**RESULT: PASS**")
      out.join("\n")
    end

    def fmt(metric, value)
      return "-" if value.nil?

      metric.end_with?("_kb") ? "#{(value / 1024.0).round(1)} MB" : format("%.1f ms", value * 1000)
    end
  end
end
