# 29 — Strategy registries for per-tag dispatch (OCP completion)

## Priority
P2

## Problem
6 remaining `case tag` dispatches map a table tag to per-table
behavior (update, transform, emit, etc.). These are OCP violations:
adding a new table's behavior requires editing every dispatch site.

## Sites
- `export/ttx_generator.rb:100` — 13-way case → generate_X_table
- `variable/static_font_builder.rb:91` — 4-way case → update_X_table
- `variation/instance_writer.rb:259` — 5-way case → table class parse
- `variation/metrics_adjuster.rb:221` — 5-way case → MVAR metric
- `woff2/table_transformer.rb:36` — 3-way case → transform_X
- `woff2/table_transformer.rb:62` — 3-way case → transform version

## Approach
Each case/when becomes a class-level dispatch hash mapping tag →
method name. The dispatch site reads from the hash. Adding a new
table means adding one line to the hash in the same file.

For dispatches that use `Tables::Registry.for(tag)` to look up a
class (like instance_writer), extend the Registry to also know how
to construct from raw data.

## Acceptance criteria
- 0 `case tag` dispatches in `lib/fontisan/`
- All specs pass
