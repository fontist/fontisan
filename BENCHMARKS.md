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
