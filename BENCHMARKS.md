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

Median of 5+ interleaved rounds, one engine per run (`FONTISAN_ENGINE`, strict). Factor = ruby time / tier time (above 1.00x is faster than Ruby; RSS rows show tier / ruby). Hard floor: native and ffi factors on audit_file, audit_dir, scan_dir must be at least 1.00x and their peak RSS must not exceed ruby's by more than 3%. Other columns are reported, not gated.

| metric | ruby | native | ffi | native factor | ffi factor | status |
|---|---|---|---|---|---|---|
| audit_file | 371.9 ms | 12.3 ms | 12.3 ms | 30.26x | 30.13x | ok |
| audit_dir | 481.6 ms | 58.6 ms | 58.2 ms | 8.22x | 8.27x | ok: gated |
| scan_dir | 239.0 ms | 60.7 ms | 58.2 ms | 3.94x | 4.11x | ok: gated |
| scan_peak_rss_kb | 58.5 MB | 56.3 MB | 57.5 MB | 0.96x | 0.98x | ok: gated |

**RESULT: PASS**

The table above is the local macOS arm64 measurement. CI measures the other platforms (`perf-gate.yml`, job `tiers`; one `perf-tiers-<platform>` artifact each); their rows are added when those runs are green.

## Published factors per platform (CI)

Native factor (ruby time / native time) from the `perf-gate.yml` `tiers` jobs, run 42233249352 on fontisan `2b648ed06153e6ba3a7babb20c62bd6778262f7a`. Median of 5+ interleaved rounds, one engine per run, hard floor 1.00x on audit_dir and scan_dir and native peak RSS at or below ruby's. Every cell below passed the floor.

| platform (runner) | audit_file | audit_dir | scan_dir | scan peak RSS (native / ruby) |
|---|---|---|---|---|
| x86_64-linux (ubuntu-22.04) | 43.14x | 33.17x | 13.58x | 0.89x |
| x86_64-linux-musl (alpine) | 21.07x | 25.64x | 10.76x | 0.90x |
| aarch64-linux (ubuntu-22.04-arm) | 45.51x | 17.16x | 7.86x | 0.84x |
| x86_64-darwin (macos-15-intel) | 36.89x | 23.06x | 7.78x | 0.94x |
| x64-mingw-ucrt (windows-2025) | 29.71x | 29.22x | 10.57x | 0.86x |
| arm64-darwin (local, Apple M2; see above) | 30.26x | 8.22x | 3.94x | 0.96x |

The arm64-darwin CI cell (macos-15) had not finished when this table was written; the local row stands in until its `perf-tiers-arm64-darwin` artifact is added. The lowest published native factor on a gated operation is 3.94x (scan_dir, arm64-darwin).

