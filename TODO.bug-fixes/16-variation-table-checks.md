# 16 — Variation table checks

## Priority
P2

## Problem
~15 `respond_to?` calls in `lib/fontisan/variation/` probe variation
table shape (`:item_variation_store`, `:region_list`, `:num_axes`,
`:advance_height_delta_set`, etc.). All variation tables are typed
BinData records — these checks should be `is_a?` or direct calls.

## Sites
- `variation/validator.rb:106/:136/:142/:144/:199/:211/:275/:278/:281/:286`
- `variation/metrics_adjuster.rb:230/:233/:310`
- `variable/metric_delta_processor.rb:224/:229/:234`
- `variable/delta_applicator.rb:296`

## Approach
1. For each variation table (Fvar, Hvar, Vvar, Mvar, Cff2, ItemVariationStore),
   verify the BinData-declared fields and methods.
2. Replace `respond_to?(:item_variation_store)` with `is_a?(Tables::Hvar)`
   or `is_a?(Tables::Vvar)` etc., then call `.item_variation_store`
   directly.
3. For optional fields (rare in variation tables), declare them with
   defaults on the BinData record.
4. For `metrics_adjuster.rb:310` `respond_to?(:number_of_h_metrics=)`,
   Hhea is a BinData record with a declared writer — drop the check.

## Acceptance criteria
- 0 `respond_to?` in `lib/fontisan/variation/` and `lib/fontisan/variable/`
- All variation specs pass
