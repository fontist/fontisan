# 17 — UFO convert and Stitcher cleanup

## Priority
P2

## Problem
~10 `respond_to?` calls in `ufo/convert/from_bin_data.rb` probe BinData
table shape. Plus 1 site in `ufo/compile/fvar.rb`.

## Sites
- `ufo/convert/from_bin_data.rb:64/:82` Name records access
- `ufo/convert/from_bin_data.rb:103/:105` Post italic_angle
- `ufo/convert/from_bin_data.rb:131` Cmap unicode_mappings
- `ufo/convert/from_bin_data.rb:149/:155` Hmtx parse/metric
- `ufo/convert/from_bin_data.rb:172` Loca parse
- `ufo/convert/from_bin_data.rb:192/:312/:323/:325` Glyph type (see TODO 15)
- `ufo/convert/from_bin_data.rb:361` Post glyph_name
- `ufo/compile/fvar.rb:23/:24` Info axes/named_instances
- `stitcher/source.rb:83/:193/:220/:228/:287/:289/:375/:377` (see TODO 14/15)

## Approach
1. Replace `name_table.respond_to?(:name_records)` with `is_a?(Tables::Name)`.
2. Replace `post.respond_to?(:italic_angle)` with `is_a?(Tables::Post)`.
3. Replace `cmap_table.respond_to?(:unicode_mappings)` with `is_a?(Tables::Cmap)`.
4. Replace `hmtx.respond_to?(:parse_with_context)` with `is_a?(Tables::Hmtx)`.
5. Replace `loca.respond_to?(:parse_with_context)` with `is_a?(Tables::Loca)`.
6. For `ufo/compile/fvar.rb`, the `font.info` is always a `Ufo::Info`.
   Check `Ufo::Info#axes` exists; if not, add it.

## Acceptance criteria
- 0 `respond_to?` in `lib/fontisan/ufo/convert/` and `lib/fontisan/ufo/compile/`
- 0 stitcher/source.rb respond_to? (split across TODO 14/15)
