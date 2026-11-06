# frozen_string_literal: true

require_relative "harness"

module FontisanBench
  # The ruby, native and ffi tiers measured in one job: the same checkout,
  # one engine per run (FONTISAN_ENGINE, strict), interleaved rounds.
  module Tiers
    TIERS = %w[ruby native ffi].freeze
    # Ops served by the engine tiers (they go through Fontisan::Reference).
    OPS = %w[audit_file audit_dir scan_dir].freeze
    # The hard floor (#160): native must be faster than Ruby on these.
    GATED_OPS = %w[audit_dir scan_dir].freeze

    # One tier of the working tree. Runs as the `head` side of run.rb.
    class TierSide < Side
      attr_reader :tier

      def initialize(tier, dir)
        super(tier, dir, ref: tier)
        @tier = tier
      end

      def env
        super.merge("FONTISAN_ENGINE" => tier, "FONTISAN_ENGINE_STRICT" => "1")
      end

      def run_once(harness_dir, corpus, only: nil)
        cmd = ["bundle", "exec", RbConfig.ruby, File.join(harness_dir, "run.rb"),
               "--corpus", corpus, "--side", "head"]
        cmd += ["--only", only.join(",")] if only
        out, err, st = Open3.capture3(env, *cmd, chdir: dir)
        raise Error, "tier #{tier} bench run failed:\n#{err}" unless st.success?

        JSON.parse(out.lines.reverse_each.find { |l| l.start_with?("{") })
      end
    end

    Row = Struct.new(:metric, :times, :factors, :status, :note, keyword_init: true)

    module_function

    # Tiers that run at all. ruby and native are required; ffi (needs the
    # cdylib) is reported when it can run and "unavailable" when it cannot.
    def sides(dir)
      TIERS.map { |t| TierSide.new(t, dir) }
    end

    def measure(sides, rounds:, harness_dir:, corpus:, only: OPS, into: nil, log: $stderr)
      m = into || Measurement.new
      rounds.times do |i|
        (i.even? ? sides : sides.reverse).each do |side|
          log.puts "round #{i + 1}/#{rounds}: #{side.name}"
          record(m, side, harness_dir, corpus, only, log)
        end
      end
      m
    end

    def record(measurement, side, harness_dir, corpus, only, log)
      measurement.record(side.name, side.run_once(harness_dir, corpus, only: only))
    rescue Error => e
      raise if side.tier != "ffi"

      log.puts "ffi tier unavailable: #{e.message.lines.first(3).join.strip}"
    end

    # Rows: per op the median per tier and the factor ruby / tier (above 1.0
    # is faster than Ruby), then the scan peak RSS per tier.
    def rows(measure)
      ops = measure.op_names.map { |op| op_row(op, TIERS.to_h { |t| [t, measure.median_op(t, op)] }) }
      ops << rss_row(TIERS.to_h { |t| [t, measure.median_rss(t)] })
    end

    def op_row(name, times)
      ruby = times["ruby"]
      factors = times.transform_values { |v| ruby && v ? ruby / v : nil }
      status = "ok"
      note = nil
      if GATED_OPS.include?(name)
        status, note = floor(times, factors)
      end
      Row.new(metric: name, times: times, factors: factors, status: status, note: note)
    end

    def floor(times, factors)
      return ["FAIL", "no ruby or native measurement"] unless times["ruby"] && times["native"]
      return ["FAIL", "native is slower than ruby"] if factors["native"] < 1.0

      %w[ok gated]
    end

    def rss_row(rss)
      status = "ok"
      note = nil
      if rss["ruby"].nil? || rss["native"].nil?
        note = "peak RSS unsupported on this platform; RSS check skipped"
        status = "skipped"
      elsif rss["native"] > rss["ruby"]
        status = "FAIL"
        note = "native peak RSS exceeds ruby's"
      else
        note = "gated"
      end
      Row.new(metric: "scan_peak_rss_kb", times: rss, factors: rss.transform_values { |v| v && rss["ruby"] ? v.to_f / rss["ruby"] : nil },
              status: status, note: note)
    end

    def failed?(rows)
      rows.any? { |r| r.status == "FAIL" }
    end

    def markdown(rows, title:, rounds:)
      out = ["## #{title}", "",
             "Median of #{rounds}+ interleaved rounds, one engine per run (`FONTISAN_ENGINE`, strict). " \
             "Factor = ruby time / tier time (above 1.00x is faster than Ruby; RSS rows show tier / ruby). " \
             "Hard floor: native factor on #{GATED_OPS.join(', ')} must be at least 1.00x and native peak RSS " \
             "must not exceed ruby's. Other columns are reported, not gated.", "",
             "| metric | ruby | native | ffi | native factor | ffi factor | status |", "|---|---|---|---|---|---|---|"]
      rows.each { |r| out << table_line(r) }
      out << ""
      out << (failed?(rows) ? "**RESULT: FAIL**" : "**RESULT: PASS**")
      out.join("\n")
    end

    def table_line(row)
      cells = TIERS.map { |t| Compare.fmt(row.metric, row.times[t]) }
      f = %w[native ffi].map { |t| row.factors[t] ? format("%.2fx", row.factors[t]) : "-" }
      status = [row.status, row.note].compact.join(": ")
      "| #{row.metric} | #{cells.join(' | ')} | #{f.join(' | ')} | #{status} |"
    end
  end
end
