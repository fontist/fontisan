# Reference facade (`Fontisan::Reference`)

Every golden is generated through this module; every engine tier serves the
same operations. Operations take a file path, never a loaded font. Read-type
results are JSON-ready: Hash with String keys sorted bytewise, Array, String,
Integer, true, false, nil. No Float (Fixed 16.16 values are raw integers) and
no clock value. `Reference.canonical_json(data)` = `JSON.pretty_generate` of the
normalised data plus a trailing newline.

Errors: the wrapped class's exception propagates unchanged (`Errno::ENOENT`,
`Fontisan::InvalidFontError`, `Fontisan::Error` "Conversion failed: ...",
`ArgumentError`). `scan` and `audit_dir` never raise for a bad font; the failure
is recorded in the row/entry. A non-path argument raises `TypeError`.

## Operations

| Op | Returns |
|---|---|
| `read(path, mode: :metadata, lazy: true)` | Array of faces (below) |
| `outline_hashes(path, index: 0)` | `{"kind"=>"glyf"/"cff"/nil, "hashes"=>[hex...]}` |
| `audit(path, validate: false)` | Array of canonical audit reports, one per face |
| `audit_dir(dir, validate: false)` | Array of `{"path"=>rel, "faces"=>[...]}` or `{"path","error"=>{"class","message"}}`, sorted by relative path; files with ttf otf ttc otc woff woff2 dfont pfa pfb extensions |
| `scan(paths)` | Array of scan rows (below); `Fontisan.scan` delegates here |
| `convert(path, to:, output:, timestamp: nil)` | the `ConvertCommand` result Hash; runs quietly; `timestamp` is passed only when `to` is `woff2` |
| `extract(path, index:, output_dir:)` | path of the extracted file (`UnpackCommand`) |
| `instance(path, coords:, timestamp: nil)` | binary String (`Instancer#instance`); `timestamp` ignored |
| `glyph_ids(path, unicodes:, text:)` | sorted unique gids; raises `Fontisan::Error` "None of the requested characters exist in <basename>" |
| `subset(path, unicodes:, text:, profile: "web", timestamp: nil)` | binary String; gids then `Subset::Builder`; `timestamp` ignored |

Three additions to existing behaviour, nothing else: optional `timestamp:`
(Unix seconds or Time) fixing `head.modified` in WOFF2 encode and
`StaticFontBuilder` (nil = today's clock behaviour); fontist's `glyph_ids` step
in `subset`; quiet `convert`.

## `read` face

`index, format, mode, lazy, file_sha256`, `tables` (`tag, length, sha256, error`
per table; sha256 nil when the loading mode gates the table out, `error` is the
exception class when loading/parsing failed), `names` (`platform_id, encoding_id,
language_id, name_id, string` decoded as fontist's `decode_name_record_manually`),
`header_fields` (`head`, `hhea`, `maxp`, `OS/2`: every field of the parsed record
with Ruby's field names; Strings that are printable ASCII stay text, others are
`"0x"+hex`), `cmap` (`count`, `sha256`, `subtable_formats`; sha256 is SHA-256 over
the sorted codepoints as big-endian uint32), `fvar` (`axes` with `*_raw` Fixed
integers, `instances` with `coordinates_raw`), `outlines` (`kind`, `count`,
`digest` = SHA-256 over the concatenated 32-byte per-glyph hashes).

Per-glyph outline hash: glyf fonts hash the glyph's byte range of `glyf`, located
via the parsed `loca` (empty glyph = hash of the empty string); CFF fonts hash the
CharString bytes of the CharStrings INDEX entry. CFF2 is not covered yet.

## Audit canonical form

`AuditCommand` with `include_codepoints: false`; `generated_at` and
`fontisan_version` dropped; Float fields become raw Fixed integers:
`font_revision` -> `font_revision_raw`, axis `min_value/default_value/max_value`
-> `*_raw` (value x 65536, rounded).

## Scan row (one per face)

`path, collection_index (nil for non-collections), sha256, format, is_collection,
num_faces, has_fvar`, `names` and `english_names` (`family_name, full_name,
subfamily_name, preferred_family, preferred_subfamily, postscript_name`;
`names` uses fontist's any-platform fallback as `FontFile`, `english_names` is
`english_name` only as `CollectionFile`; `english_names` is nil for
non-collections), `variable_instances` (`family, style, full_name`, fontist's
RIBBI rule, from a second full-mode load), `validation` (`profile, valid,
status, issues[severity, category, message, location], error_summary` = fontist's
`"category: message; ..."`), and `errors`:

- `font_file`: what `FontFile.extract_font_info_from_path` would raise (only
  rows of the face it reads: non-collection or index 0), as `{class, message,
  cause}`; message `"Font file could not be parsed: #<Class: msg>."`.
- `collection_file`: what `CollectionFile.from_path` would raise for the file
  (same on every row of the file): "File is not a recognized font collection
  (TTC/OTC/dfont)" for non-collections, "Font collection could not be loaded: ..."
  or "Font collection failed indexability validation (first font): ...".
- `collection_member`: error of the lazy:false metadata load that
  `CollectionFile#[]` performs for this face, `{class, message}`.
