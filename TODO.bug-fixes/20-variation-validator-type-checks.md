# 20 — Variation validator type checks

## Priority
P2

## Problem
11 `respond_to?` calls in `lib/fontisan/variation/validator.rb` probe
typed BinData records (Cff2, Hvar, ItemVariationStore, RegionList).
The checks were left in place in PR #136 because `validator_spec.rb`
uses minimal doubles without all the methods stubbed.

## Sites
- :106 `cff2.respond_to?(:num_axes)` — Cff2 always declares num_axes
- :136 `table.respond_to?(:item_variation_store)` — Hvar/Vvar/Mvar all do
- :142 `store.respond_to?(:region_list)` — ItemVariationStore has it
- :144 `region_list.respond_to?(:axis_count)` — RegionList has it
- :199 `hvar.respond_to?(:item_variation_store)` — Hvar has it
- :211 `store.respond_to?(:item_variation_data)` — ItemVariationStore has it
- :275/:278/:281/:286 region/region_list/region_axes checks

## Approach
1. Replace `respond_to?` with direct method calls.
2. Wrap in begin/rescue NoMethodError OR pre-validate with is_a?.
3. Update `validator_spec.rb` doubles to provide all methods the
   validator now calls directly. Use Struct-based fakes if helpful.

## Acceptance criteria
- 0 `respond_to?` in `lib/fontisan/variation/validator.rb`
- All variation specs pass
