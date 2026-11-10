# Corpus triage (fontist/fontisan#156, card 0b)

Every audit check was run over the `ci` tier and the suspect results were reviewed.
Each entry is either `fixed` (committed on this branch or already on main) or
`known_reference_bug` (Ruby's output is kept as the golden; a native tier reproduces
it and the golden carries the id in its `known_reference_bug` field). Malformed fonts
are triaged by card 0e.

## Fixed

| id | status | evidence | affected fonts |
|---|---|---|---|
| FIXED-LOCA-SIZE | fixed | 38267b5 | loca size handling |
| FIXED-WOFF2-COLLECTION | fixed | 1de68d2 | WOFF2 collection mode |
| FIXED-FONTWRITER-CHECKSUM | fixed | c61a52d, `spec/corpus/fix_font_writer_checksum_spec.rb`: write, reload, write is now identical (`checkSumAdjustment` was not idempotent) | every font rewritten by `FontWriter` |
| FIXED-SFNT-TABLE-DATA | fixed | f970575, `fix_sfnt_table_data_spec.rb` | StaticFontBuilder input |
| FIXED-WOFF-TABLES | fixed | d91ecab, `fix_woff_table_classes_spec.rb`: WoffFont parses glyf, loca, CFF | WOFF fonts |
| FIXED-CFF-CHARSTRING-CACHE | fixed | 58537a2, `fix_cff_charstring_cache_spec.rb`: INDEX parsed once, NotoSansJP audit from minutes to about 1.8 s | CFF fonts |
| FIXED-NAME-EMPTY | fixed | 585e298, `fix_name_empty_table_spec.rb` | quirk-empty-name-table |
| FIXED-HINTING-CVT | fixed | 06d7033, `fix_hinting_cvt_spec.rb`: false "no cvt" because the tag is `"cvt "` | 21 fonts |
| FIXED-CMAP-SHORT | fixed | 1ba7332, `fix_cmap_short_table_spec.rb`: crash on a short cmap | quirk-empty-cmap-table |
| FIXED-AUDIT-ADDRESSES | fixed | 5d2a171, `audit_message_masking_spec.rb`: object addresses in messages made output non-deterministic (a determinism fix, not a font bug) | all |
| FIXED-SWEEP-MAXP-VERSION | fixed | `fix_ruby_sweep_spec.rb`: `MaxpCheck` formatted a `BinData::Int32be` with `to_s(16)` and crashed (fatal, no location) whenever the version warning fired, e.g. `audit(validate: true)` on a font with glyf dropped; now a warning at `maxp.version` | 23 drop-sweep audit cases |
| FIXED-SWEEP-INSTANCER-TABLES | fixed | `fix_ruby_sweep_spec.rb`: `TrueTypeInstancer` leaked `undefined method '[]'/'unpack' for nil` when head, hhea, hmtx, maxp or loca was missing; now `MissingTableError` "Font missing required <tag> table" | variable TTFs with one of those tables dropped |
| FIXED-SWEEP-WOFF2-LOCA | fixed | `fix_ruby_sweep_spec.rb`: `Woff2Encoder` kept short loca when the 4-byte-padded glyf no longer fit (offset/2 wrapped past 16 bits, `unpack1 for nil` or a corrupt glyph stream); now long loca is chosen | glyf above 131,070 bytes padded, short-loca source (source-sans-3-vf-upright-ttf without fvar/gvar) |
| FIXED-SWEEP-CFF-NAME | fixed | `fix_ruby_sweep_spec.rb`: the `UnnamedFont` fallback was a UTF-8 literal, so TTF to OTF without a name table raised `item 0 must have BINARY encoding`; now binary | any font converted to OTF with no name table |
| FIXED-SWEEP-CMAP-VALIDATOR | fixed | `fix_ruby_sweep_spec.rb`: `cmap_glyph_indices` called a method on a missing cmap ("Exception during check execution: NoMethodError"); now skipped (the missing table is reported by `required_tables`) | any font validated without cmap |

## Known reference bugs

| id | status | evidence | affected fonts |
|---|---|---|---|
| T1-READ | known_reference_bug | `Type1Font` lacks `has_table?` (pfb raises NoMethodError); pfa is not detected (InvalidFontError). Type 1 is outside native scope. | fonttools-test-t1-pfb, fonttools-test-t1-pfa |
| WOFF-CHECKS | known_reference_bug | `table_directory` check (search_range on the WOFF header) and `opentype_conformance` (`font.tables` on WoffFont/Woff2Font) crash, giving a fatal "Check ... failed to execute". | fonttools-test-woff, fonttools-test-woff2, source-sans-3-regular-{otf,ttf}-{woff,woff2} |
| MVAR-OFFSET | known_reference_bug | `Tables::Mvar` reads the store offset as uint32 and raises EOFError; goldens use the spec Offset16. Flag for 0c (the instancer may use it). | noto-sans-vf-wdth-wght, source-sans-3-vf-italic-ttf, source-sans-3-vf-upright-cff2, source-sans-3-vf-upright-ttf |
| CFF2-PARSER | known_reference_bug | `Tables::Cff2` parses the Global Subr INDEX with the CFF1 layout ("Invalid INDEX offSize: 159", glyph_count 0); goldens use the spec-based parser. | source-sans-3-vf-upright-cff2 |
| NAME-FORMAT1 | known_reference_bug | name format 1 storage is misread. | quirk-name-format-1 |
| NAME-MAC-DECODE | known_reference_bug | Mac names are decoded as ASCII with replacement characters (the facade copies fontist on purpose). | names-mac-roman-only |
| NAME-FULL-REGULAR | known_reference_bug | the info-level full-name check fires when the full name omits "Regular" (arguably a false positive). Tagged automatically from the audit message. | every font whose validate audit has "Full name ... doesn't match Family + Subfamily" |
| CHECKSUM-BINDATA | known_reference_bug | `table_directory` check `validate_checksums` calls `entry.checksum.to_s(16)` on a `BinData::Uint32be`, which takes no argument, so `audit(validate: true)` on a bad checksum yields one fatal "Check table_directory failed to execute: ArgumentError". Pinned in `read/_diverge/bad-checksum-validate.json`. | malformed-bad-checksum |

## Reviewed, no entry

maxStackElements 0 with fpgm (real), missing gasp and HVAR on Mona Sans, panose zeros,
no DFLT script, ps_prefix warnings on the names-* fixtures.
