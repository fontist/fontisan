# 12 — Type 1 generators duck-typing cleanup

## Priority
P0

## Problem
50+ `respond_to?` calls in `lib/fontisan/type1/` check for methods that
don't exist on the BinData Name/OS/2/Post tables. Every check returns
false and the generators silently fall through to empty/unknown values.

## Sites (by file)

### `pfm_generator.rb` (10)
- :506 `respond_to?(:copyright)` — Name table has no `#copyright`
- :521 `respond_to?(:full_font_name)` — Name table has no `#full_font_name`
- :523 `respond_to?(:font_family)` — Name table has no `#font_family`
- :525 `respond_to?(:postscript_name)` — Name table has no `#postscript_name`
- :541/:543 `respond_to?(:us_weight_class)` / `respond_to?(:weight_class)` — OS/2 has neither
- :372/:374 `respond_to?(:cap_height)` / `respond_to?(:s_typo_ascender)` — same
- :382 `respond_to?(:x_height)` — OS/2 has no `#x_height`
- :567 `respond_to?(:is_fixed_pitch)` — Post has no `#is_fixed_pitch`
- :148 `respond_to?(:unicode_mappings)` — Cmap DOES have this; check unnecessary

### `pfa_generator.rb` (6)
- :137/:142 `respond_to?(:version_string)` / `:copyright` on Name
- :164 `respond_to?(:typo_ascender)` on OS/2
- :181/:189 `respond_to?(:weight_class)` on OS/2
- :307 `respond_to?(:points)` on glyph — same broken pattern as #20

### `pfb_generator.rb` (3)
- :162/:170 `respond_to?(:weight_class)` on OS/2
- :276 `respond_to?(:points)` on glyph

### `afm_generator.rb` (16)
- :170/:173 `respond_to?(:underline_position)` / `:underline_thickness` on Post
- :255/:257 `respond_to?(:us_weight_class)` / `:weight_class`
- :283 `respond_to?(:italic_angle)`
- :297 `respond_to?(:is_fixed_pitch)`
- :311/:323 `respond_to?(:version_string)` / `:copyright` on Name
- :339/:341/:343 `respond_to?(:unicode_mappings)` / `:unicode_bmp_mapping` / `:subtables` on Cmap
- :346/:348/:352 subtable field probes
- :368/:370/:371 `respond_to?(:font_bounding_box)` / `:x_min` / `:y_min` on Head
- :393 `respond_to?(:parse_with_context)` on Loca
- :401 `respond_to?(:glyph_for)` on Glyf
- :405/:407/:408 `respond_to?(:bounding_box)` / `:x_min` etc. on glyph

### `inf_generator.rb` (10)
- :187/:202/:217/:269/:281/:293/:305 Name/Post field probes
- :229/:231 OS/2 weight class probes
- :257 `respond_to?(:italic_angle)`

### `generator.rb` (1)
- :203 `respond_to?(:postscript_name)` on Name

### `decryptor.rb` (1)
- :115 `respond_to?(:b)` on String — always true for Ruby strings

## Approach
1. Add a `NameIds` constants module if not present (NAME_COPYRIGHT=0,
   NAME_FONT_FAMILY=1, NAME_FULL_FONT_NAME=4, NAME_VERSION=5,
   NAME_POSTSCRIPT_NAME=6, NAME_MANUFACTURER=8, NAME_LICENSE=13).
2. Replace `name_table.respond_to?(:X) ? name_table.X(1) : ""` with
   `name_table&.english_name(NAME_ID_X) || ""`.
3. For OS/2 fields, declare the BinData field accessor (most already
   exist) and access directly: `os2&.us_weight_class`.
4. For Post fields, same: `post&.italic_angle`.
5. For Cmap, `cmap.unicode_mappings` is the documented API — drop the
   `respond_to?` and just call it (nil guard at the boundary).
6. For Loca parse_with_context, Loca responds to it always — drop the
   check.
7. For glyph bounding boxes, use the typed SimpleGlyph/CompoundGlyph
   `bounding_box` method (always present).
8. For `glyph.respond_to?(:points)`, see TODO 15 — the underlying bug
   is fixed there.

## Acceptance criteria
- 0 `respond_to?` in `lib/fontisan/type1/` (excluding `respond_to_missing?`)
- All Type 1 generation specs pass with real Libertinus fixture
- AFM/PFM/PFA/PFB/INF output now contains real Name table values
  (previously was empty for most fields)
