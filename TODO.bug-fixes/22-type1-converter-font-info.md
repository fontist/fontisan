# 22 — Type1Converter font_info fields

## Priority
P2

## Problem
6 `respond_to?` calls in `lib/fontisan/converters/type1_converter.rb`
probe `font_info` for typed fields (family_name, full_name, version,
copyright, weight, notice). The font_info is always a `Type1::FontInfo`
model — these fields are declared.

## Sites
- :723/:728/:733/:738/:744/:749 font_info field probes

Plus 1 site at :160: `font.font_dictionary.respond_to?(:reload)` —
FontDictionary is a typed class.

## Approach
1. Verify `Type1::FontInfo` declares all the probed fields.
2. Replace `font_info.respond_to?(:family_name)` with direct call.
3. For `font_dictionary.respond_to?(:reload)`, use `is_a?(Type1Font::FontDictionary)`.

## Acceptance criteria
- 0 `respond_to?` in `lib/fontisan/converters/type1_converter.rb`
- All Type1 converter specs pass
