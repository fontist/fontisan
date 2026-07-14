# 13 — Hint extractor duck-typing cleanup

## Priority
P1

## Problem
15 `respond_to?` calls in `lib/fontisan/hints/postscript_hint_extractor.rb`
probe PrivateDict fields that are always declared on the BinData record.
Plus 2 sites in `postscript_hint_extractor.rb:60-62` that probe Charstring
shape (`:data` vs `:bytes`).

## Sites
- :60/:62 `charstring.respond_to?(:data)` / `:bytes` — Charstring has one shape
- :292/:296/:300/:304 `respond_to?(:blue_values)` / `:other_blues` / `:family_blues` / `:family_other_blues`
- :308/:312/:316 `respond_to?(:blue_scale)` / `:blue_shift` / `:blue_fuzz`
- :320/:324 `respond_to?(:std_hw)` / `:std_vw`
- :328/:332 `respond_to?(:stem_snap_h)` / `:stem_snap_v`
- :336/:340 `respond_to?(:force_bold)` / `:language_group`

## Approach
1. Verify which fields are declared on `Tables::Cff::PrivateDict`.
2. For declared fields, drop the `respond_to?` and read directly with
   nil-coalescence: `private_dict.blue_values`.
3. For undeclared fields (rare BinData optional), either declare them
   with a default `nil` or remove the dead branch.
4. For Charstring, standardize on one accessor (probably `#data`).

## Acceptance criteria
- 0 `respond_to?` in `lib/fontisan/hints/`
- All hint extraction specs pass
