# 01 — CFF Expert charset placeholder

## Priority
P0

## Problem
`Tables::Cff::Charset#load_expert_charset` and `load_expert_subset_charset`
(charset.rb:219-245) are placeholders that generate sequential SID-based
names instead of using the correct Adobe CFF spec predefined SID lists.

Any CFF font using predefined charset format 1 (Expert) or format 2
(ExpertSubset) gets **wrong glyph names** for all glyphs except .notdef.

## Goal
Replace both methods with the complete SID lists from Adobe CFF spec
(TN 5176) Section 19, extracted to a data module for separation.

## Approach
- Add the Expert and ExpertSubset SID arrays to a new data module
  `Tables::Cff::ExpertCharsets` in `lib/fontisan/tables/cff/expert_charsets.rb`
- `load_expert_charset` uses `ExpertCharsets::EXPERT`
- `load_expert_subset_charset` uses `ExpertCharsets::EXPERT_SUBSET`

## Acceptance criteria
- Expert charset produces the correct 228-entry SID list
- ExpertSubset charset produces the correct 87-entry SID list
- Spec covers both predefined charsets produce correct glyph names
