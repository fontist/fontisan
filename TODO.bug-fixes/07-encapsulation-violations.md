# 07 — Encapsulation violations (instance_variable_get/set, send to private)

## Priority
P0

## Problem
The codebase has 14+ `instance_variable_get` calls, 4 `instance_variable_set`
calls, and 3 `send` calls to methods that should be accessed through public
APIs. These break encapsulation and make the code fragile to refactoring.

## Specific violations

### instance_variable_get (should use public accessors)
- `cff2.rb:343-344` — reads `@data_size`, `@off_size` from Cff2::Index
- `cff/table_builder.rb:102` — reads `@start_offset` from Cff::Index
- `dump_table_command.rb:35` — reads `@table_data` from font (public reader exists!)
- `truetype_hint_extractor.rb:188,205,222` — reads `@table_data` from font
- `validator.rb:439` — reads `@filename` from font
- `converter.rb:83` — reads `@parsed` from charstring

### instance_variable_set (should use constructors or public setters)
- `instance_writer.rb:233` — sets `@table_data` on temp font
- `outline_converter.rb:425` — sets `@table_data` on temp font
- `base_record.rb:41` — sets `@raw_data` on BaseRecord
- `glyf.rb:56` — sets `@glyphs_cache` on BinData record

### send to potentially private methods
- `exporter.rb:191` — `send(:encode_binary, ...)`

## Approach
1. Add missing public readers where they don't exist (Index#data_size, etc.)
2. Replace all instance_variable_get/set with public method calls
3. Replace send with direct method calls or public dispatch

## Acceptance criteria
- 0 `instance_variable_get` in lib/fontisan/
- 0 `instance_variable_set` in lib/fontisan/
- 0 `send` to private methods in lib/fontisan/
