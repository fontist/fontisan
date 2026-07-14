# 19 — Hand-rolled serialization migration to lutaml-model

## Priority
P2

## Problem
5 sites hand-roll `to_h` / `to_hash` on model classes, bypassing
lutaml-model's declarative serialization. Violates the absolute rule:
"NEVER write `def to_h`, `def to_hash`, `def from_h`, `def from_hash` on
a model class."

## Sites
- `lib/fontisan/tables/hmtx.rb:54` `def to_h` — manual hash from instance vars
- `lib/fontisan/tables/cff/dict.rb:112` `def to_h` — manual hash
- `lib/fontisan/type1/generator.rb:167` `def to_hash` — manual result hash
- `lib/fontisan/type1/conversion_options.rb:105` `def to_hash` — manual hash
- `lib/fontisan/ufo/point.rb:32` `def to_h` — manual hash for GLIF output

## Approach
For each model class:

1. Make it inherit from `Lutaml::Model::Serializable`.
2. Replace instance variables with `attribute :name, :type` declarations.
3. Replace `to_h` / `to_hash` with a `key_value do ... end` mapping block.
4. Callers use `model.to_hash` (framework-provided) instead of
   hand-rolled `to_h`.

### Special considerations

- **`Ufo::Point#to_h`**: produces a Hash for GLIF XML output. The
  lutaml-model `key_value` mapping with `:x`, `:y`, `:type`, `:smooth`
  fields handles this. The `smooth: true` only-if-set behavior is
  modeled via lutaml-model's optional attribute pattern.

- **`Type1::Generator#to_hash`**: this is a *result* hash, not a model
  serialization. Rename to `#to_result_hash` (or expose individual
  accessors) to clarify it's not lutaml-model-shaped. OR convert the
  result to a `Models::Type1GenerationResult` model.

- **`Type1::ConversionOptions#to_hash`**: this is a value object
  representing conversion options. Migrate to lutaml-model with
  `attribute` declarations for each option.

- **`Tables::Hmtx#to_h`**: BinData records already provide `snapshot`.
  Remove the hand-rolled `to_h` and let callers use `snapshot`.

- **`Tables::Cff::Dict#to_h`**: same — use `snapshot`.

## Acceptance criteria
- 0 `def to_h` / `def to_hash` in `lib/fontisan/` (excluding lutaml-model
  framework methods)
- All serialization goes through `lutaml-model`
