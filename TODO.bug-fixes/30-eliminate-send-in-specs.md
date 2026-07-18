# 30 — Eliminate .send(:private_method) calls in specs

## Priority
P1

## Problem
288 `.send(:method_name, ...)` calls in spec files bypass
encapsulation to test private methods directly. This violates the
"never use private send methods" rule.

## Approach
For each method tested via `.send()`:
1. Make it public (move above `private` keyword)
2. Replace `.send(:method, args)` with `.method(args)` in specs

Rationale: if a method is important enough to test directly,
it should be part of the public API.

## Top files by send count
- type1_converter_spec.rb (66)
- cff2/table_builder_spec.rb (34)
- format_converter_spec.rb (17)
- type1_property_spec.rb (13)
- outline_converter_spec.rb (11)
- conversion_options_spec.rb (10)
- info_command_spec.rb (10)
- base_command_spec.rb (10)
- pattern_analyzer_spec.rb (10)
- variation/converter_spec.rb (10)
- woff2_font_spec.rb (10)
- Plus ~15 more files

## Acceptance criteria
- 0 `.send(:` calls in spec/
- All tested methods are public
- All specs pass
