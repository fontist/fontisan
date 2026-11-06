# Benchmarks

Reference corpus `ci` tier benches for the #157 operations (`rake bench`).

- fontisan SHA: `6806181894f8dd9d4fa4cba3ea3cf3ffef59d341`
- Ruby: 3.4.8 (arm64-darwin25)
- Runner: darwin25, Apple M2, 8 cores
- Rounds: 5 (median per op); each op is the fastest of repeated calls (at least 3 calls or 0.25 s of measured time)

| operation | median |
|---|---|
| table_parse | 5.9 ms |
| names | 5.0 ms |
| cmap_coverage | 2.7 ms |
| audit_file | 368.2 ms |
| audit_dir | 496.3 ms |
| scan_dir | 265.6 ms |
| vf_instance | 141.6 ms |
| woff2_decode | 93.5 ms |
| convert_roundtrip | 109.2 ms |
| woff2_encode | 994.6 ms |
| scan_peak_rss (directory scan) | 60.4 MB |

## Engine tier factors

- Ruby: 3.4.8 (arm64-darwin25); local macOS arm64 (Apple M2), not CI
- fontisan SHA: `d8e13aae38212cb0507cee03d6ce8fbbf53061e2`

Median of 5+ interleaved rounds, one engine per run (`FONTISAN_ENGINE`, strict). Factor = ruby time / tier time (above 1.00x is faster than Ruby; RSS rows show tier / ruby). Hard floor: native factor on audit_dir, scan_dir must be at least 1.00x and native peak RSS must not exceed ruby's. Other columns are reported, not gated.

| metric | ruby | native | ffi | native factor | ffi factor | status |
|---|---|---|---|---|---|---|
| audit_file | 371.9 ms | 12.3 ms | 12.3 ms | 30.26x | 30.13x | ok |
| audit_dir | 481.6 ms | 58.6 ms | 58.2 ms | 8.22x | 8.27x | ok: gated |
| scan_dir | 239.0 ms | 60.7 ms | 58.2 ms | 3.94x | 4.11x | ok: gated |
| scan_peak_rss_kb | 58.5 MB | 56.3 MB | 57.5 MB | 0.96x | 0.98x | ok: gated |

**RESULT: PASS**

The table above is the local macOS arm64 measurement. CI measures the other platforms (`perf-gate.yml`, job `tiers`; one `perf-tiers-<platform>` artifact each); their rows are added when those runs are green.
