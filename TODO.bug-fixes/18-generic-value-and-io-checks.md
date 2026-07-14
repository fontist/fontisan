# 18 — Generic value and IO checks

## Priority
P3

## Problem
~20 `respond_to?` calls probe generic value shape (`:to_i`, `:bytesize`,
`:to_binary_s`, `:empty?`, `:b`) or IO capabilities (`:seek`, `:rewind`).
Some are valid duck-typing at system boundaries; others are dead
defensive code.

## Sites
### Generic value conversion
- `export/ttx_generator.rb:67/:474` `respond_to?(:to_i)`
- `export/transformers/name_transformer.rb:47`
- `export/transformers/post_transformer.rb:36`
- `export/transformers/head_transformer.rb:45`
- `export/transformers/maxp_transformer.rb:48`
- `export/transformers/os2_transformer.rb:104`
- `export/transformers/hhea_transformer.rb:44`
- `export/transformers/font_to_ttx.rb:106`
- `export/exporter.rb:184/:204/:209` `respond_to?(:to_binary_s)` / `:checksum`
- `export/ttx_generator.rb:296/:435`

### String/bytes shape
- `utilities/padding.rb:30/:55` `respond_to?(:bytesize)`
- `utilities/brotli_wrapper.rb:136` `respond_to?(:bytesize)`
- `type1/decryptor.rb:115` `respond_to?(:b)` — String always has `.b`

### IO capability
- `binary/base_record.rb:27/:37` `respond_to?(:empty?)` / `:rewind`
- `tables/cff/index.rb:61` `respond_to?(:seek)`

### Charstring shape
- `hints/postscript_hint_extractor.rb:60/:62` (see TODO 13)

### Pattern matching
- `optimizers/charstring_rewriter.rb:130` `respond_to?(:positions)`

## Approach
1. For `respond_to?(:to_i)`, replace with `Integer(value) rescue value`
   — accepts Integer-coercible values, falls back to original.
2. For `respond_to?(:bytesize)`, narrow the type at the boundary: accept
   `String` only, call `.bytesize` directly.
3. For `respond_to?(:to_binary_s)`, all BinData records respond to it.
   Drop the check; if a non-BinData object is passed, fix the caller.
4. For `respond_to?(:b)` on String, just call `.b` (String always has it).
5. For IO `respond_to?(:seek)` / `:rewind`, accept `IO` / `StringIO`
   only. Convert String inputs to StringIO at the boundary.
6. For `respond_to?(:empty?)`, the BinData array always responds — drop.

## Acceptance criteria
- 0 unnecessary `respond_to?` in `lib/fontisan/export/`, `lib/fontisan/utilities/`,
  `lib/fontisan/binary/`
- Where duck-typing is genuinely needed at a system boundary, document
  it with a comment
