---
title: validate-collection
---

# validate-collection

Validate the structural integrity of a TTC / OTC / dfont collection:
face count, per-face glyph cap, and optional cmap-union size.

This is a collection-level counterpart to
[validate](/cli/validate), which runs profile-based per-face quality
checks (OpenType compliance, hint validity, etc.). Use
`validate-collection` when you care about the *shape* of the
collection (number of faces, glyph-cap overflows, codepoint coverage)
rather than per-face quality.

## Quick Reference

```bash
fontisan validate-collection <path> [options]
```

The command exits `0` when every requested check passes and `1` when
any check fails. With no options, only the per-face glyph cap is
checked (default `65,535`).

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--expected-faces N` | (none) | Require exactly `N` faces in the collection. |
| `--max-glyphs N` | `65535` | Per-face glyph cap (`maxp.numGlyphs`). Faces over this cap fail. |
| `--expected-cmap-union N` | (none) | Require the union of cmap codepoints across all faces to be at least `N`. |

## Examples

```bash
# Glyph-cap-only check (default behaviour, no optional checks)
fontisan validate-collection family.ttc

# Require exactly 5 faces
fontisan validate-collection family.ttc --expected-faces 5

# Tighter per-face glyph cap
fontisan validate-collection family.ttc --max-glyphs 60000

# Require at least 100,000 codepoints covered across all faces
fontisan validate-collection family.ttc --expected-cmap-union 100000
```

## Sample output

```
face 0:    3541 glyphs ✓
face 1:   21048 glyphs ✓
face 2:     991 glyphs ✓
all 3 faces within 65535-glyph cap ✓
face_count: ✓
cmap union: 24580 cps ✓
```

When a check fails, the marker becomes `✗` and a message is printed
in parentheses; the exit code is `1`.

## Programmatic access

The command is a thin wrapper around
`Fontisan::Collection::Reader`, which exposes per-face metadata
directly:

```ruby
reader = Fontisan::Collection::Reader.open("family.ttc")
reader.face_count                  # => 3
reader.stats.map(&:glyph_count)    # => [3541, 21048, 991]
reader.cmap_union.size             # => 24580
```

Use the command-class directly when you want structured results
without stdout:

```ruby
cmd = Fontisan::Commands::ValidateCollectionCommand.new(
  input: "family.ttc",
  expected_faces: 3,
)
exit_code = cmd.run           # 0 or 1
cmd.checks                    # => [#<Check name=:face_count passed=true ...>, ...]
```

## See also

- [validate](/cli/validate) — per-face profile-based checks (OpenType
  compliance, hint validity, etc.)
- [pack](/cli/pack) / [unpack](/cli/pack) — create and extract
  collections
