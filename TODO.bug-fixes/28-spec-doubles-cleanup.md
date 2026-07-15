# 28 — Spec doubles cleanup

## Priority
P3

## Problem
**343 `double()` / `instance_double()` calls remain in specs** despite
the absolute rule "NEVER use `double()` in specs". Per file:

| File | Count |
|------|-------|
| spec/fontisan/converters/type1_converter_spec.rb | 58 |
| spec/fontisan/converters/format_converter_spec.rb | 33 |
| spec/fontisan/converters/type1_property_spec.rb | 28 |
| spec/fontisan/tables/cff2/table_builder_spec.rb | 25 |
| spec/fontisan/variation/validator_spec.rb | 24 |
| spec/fontisan/variation/subsetter_spec.rb | 17 |
| spec/fontisan/variation/metrics_adjuster_spec.rb | 15 |
| spec/fontisan/variation/converter_spec.rb | 14 |
| spec/fontisan/collection/variable_font_builder_spec.rb | 12 |
| spec/fontisan/converters/woff2_encoder_spec.rb | 11 |
| spec/fontisan/collection/table_deduplicator_spec.rb | 9 |
| spec/fontisan/collection/table_analyzer_spec.rb | 7 |
| spec/fontisan/tables/cff/cff_glyph_spec.rb | 6 |
| spec/fontisan/hints/truetype_hint_extractor_spec.rb | 6 |
| spec/fontisan/commands/unpack_command_spec.rb | 6 |
| (other files, 5 or fewer each) | ~74 |

## Approach
Each spec migration replaces `double("Foo", attr: value)` with either:
1. A real instance of the doubled class, OR
2. A `Struct`-based fake in a uniquely-named module (e.g., `XxxFakes::Foo`).
3. The shared `SpecHelpers::FakeFont` where the double is font-shaped.

PR #135/#136/#137 migrated ~10 spec files this way. The pattern is
established; remaining files are mechanical work.

## Acceptance criteria
- 0 `double()` / `instance_double()` in `spec/fontisan/`
- All specs pass
