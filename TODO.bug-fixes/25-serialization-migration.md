# 25 — Serialization migration to lutaml-model

## Priority
P2

## Problem
6 sites hand-roll `to_h` / `to_hash` / `to_json` on model classes,
violating the absolute rule against hand-rolled serialization.

## Sites
- `lib/fontisan/tables/hmtx.rb:54` `MetricRecord#to_h` — BinData inner record
- `lib/fontisan/tables/cff/dict.rb:112` `Dict#to_h` — internal hash accessor
- `lib/fontisan/type1/generator.rb:167` `Generator#to_hash` — option snapshot
- `lib/fontisan/type1/conversion_options.rb:105` `ConversionOptions#to_hash` — option snapshot
- `lib/fontisan/ufo/point.rb:32` `Point#to_h` — GLIF XML output
- `lib/fontisan/export/exporter.rb:65` `Result#to_json` — export payload

## Approach (per site)

### Hmtx::MetricRecord#to_h
BinData records expose `snapshot` returning a hash. Remove `to_h`,
update callers (in stitcher/, type1/) to use `metric.snapshot` or
extract `[:advance_width]` / `[:lsb]` directly.

### Cff::Dict#to_h
`Dict` wraps an internal `@dict` hash. `to_h` returns `@dict.dup`.
Rename to `#raw_hash` (or `#pairs`) to make clear it's an accessor,
not serialization. Update callers in `cff/table_builder.rb`,
`cff/private_dict_writer.rb`.

### Type1::Generator#to_hash and Type1::ConversionOptions#to_hash
These are option snapshots, not wire serialization. Rename to
`#to_options_hash` to clarify intent. Migrate `ConversionOptions`
to a `Lutaml::Model::Serializable` for declarative attribute
management.

### Ufo::Point#to_h
Used for GLIF XML output. Migrate `Ufo::Point` to inherit from
`Lutaml::Model::Serializable` with `:x`, `:y`, `:type`, `:smooth`
attributes and a `key_value` mapping.

### Export::Result#to_json
Used for export payload. Migrate to a `Models::ExportResult`
lutaml-model with JSON mapping.

## Acceptance criteria
- 0 `def to_h` / `def to_hash` / `def to_json` in `lib/fontisan/`
- All serialization goes through lutaml-model or BinData snapshot
- All affected specs pass
