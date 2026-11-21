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

Native factor (ruby time / native time) from the `perf-gate.yml` `tiers` jobs, run 42807490330 on fontisan `5e1bd0fc0b3f2373ca6d53d7360e28d4497bbfe2`. Median of 5+ interleaved rounds, one engine per run, hard floor 1.00x on audit_file, audit_dir and scan_dir and native peak RSS at or below ruby's. Every cell below passed the floor.

| platform (runner) | audit_file | audit_dir | scan_dir | scan peak RSS (native / ruby) |
|---|---|---|---|---|
| x86_64-linux (ubuntu-22.04) | 44.80x | 21.32x | 15.39x | 0.86x |
| x86_64-linux-musl (alpine) | 25.91x | 14.67x | 11.27x | 0.89x |
| aarch64-linux (ubuntu-22.04-arm) | 46.80x | 11.32x | 8.27x | 0.88x |
| x86_64-darwin (macos-15-intel) | 39.82x | 10.25x | 9.51x | 0.94x |
| x64-mingw-ucrt (windows-2025) | 30.32x | 17.12x | 10.89x | 0.85x |
| arm64-darwin (macos-15) | 40.39x | 6.81x | 5.51x | 0.91x |

All six rows now come from CI. arm64-darwin has no committed baseline yet, so it is checked against the 1.00x floor only. The lowest published native factor on a gated operation is 5.51x (scan_dir, arm64-darwin).


## Compile pipeline (TODO.remaining/20)

- Ruby: 4.0.7 (arm64-darwin23); local macOS arm64, single runs (runner
  noise +-20%; rerun the scripts rather than comparing one line)
- Scripts: `benchmark/compile_benchmark.rb` (also `--large` for 65k),
  `benchmark/collection_benchmark.rb`, `benchmark/fonttools_compare.rb`

fontisan in-memory compiler (synthetic 1-contour glyphs, 1 UPM):

| op | 1k glyphs | 10k glyphs |
|---|---|---|
| TTF compile | ~30-40 ms (25-31k glyphs/s) | ~190 ms (~50k glyphs/s) |
| OTF compile | ~25-30 ms (34-40k glyphs/s) | ~178 ms (~56k glyphs/s) |
| CFF2 OTF compile | ~24 ms (41k glyphs/s) | ~183 ms (~55k glyphs/s) |

Collection assembly (dedup pack, after compiling N x 1000-glyph faces):
4 faces ~17 ms (output 74% smaller than the raw faces), 8 faces ~10 ms
(86% smaller).

fontisan vs ufo2ft (fontTools), same on-disk synthetic UFO, full
read+compile pipeline, 1000 glyphs, single runs:

| op | fontisan | ufo2ft | fontisan output vs ufo2ft |
|---|---|---|---|
| TTF | ~0.7-1.3 s | ~0.7-1.0 s | 32,752 B vs 40,532 B (smaller) |
| OTF | ~1.2-2.9 s | ~0.7-1.1 s | 23,752 B vs 13,616 B (larger) |

The gap sits almost entirely in the UFO reader: compiling the SAME font
from memory costs ~30 ms, so ~95% of fontisan's disk-path time is .glif
parsing (~1.2 ms/glyph). The TODO's ">2x slower than fontTools triggers
optimization" threshold is brushed by the OTF row on some runs; if it
holds under median-of-N measurement, the hot path to optimize is
Ufo::Reader, not the compilers.
