---
title: Migration Guides
---

# Migration Guides

Migrating from another font tool? These guides will help you transition to Fontisan.

## Available Guides

### From fonttools (Python)

[→ Migrate from fonttools](/guide/migrations/fonttools)

The most comprehensive migration guide covering:
- API equivalents for `TTFont`, `fontTools.varLib`, etc.
- CLI command mapping
- Feature comparison table
- Common workflows

### From extract_ttc

[→ Migrate from extract_ttc](/guide/migrations/extract-ttc)

Fontisan fully supersedes extract_ttc:
- Identical `ls` and `info` commands
- More powerful `unpack` with format conversion
- Works on TTF/OTF files too
- Table sharing statistics

### From otfinfo (lcdf-typetools)

[→ Migrate from otfinfo](/guide/migrations/otfinfo)

Command equivalents for lcdf-typetools users:
- `otfinfo -i` → `fontisan info`
- `otfinfo -s` → `fontisan scripts`
- `otfinfo -f` → `fontisan features`
- `otfinfo -g` → `fontisan glyphs`

### From Font-Validator

[→ Migrate from Font-Validator](/guide/migrations/font-validator)

Validation profile mapping:
- Auto mode → `fontisan validate -t indexability`
- Full mode → `fontisan validate -t production`
- Web mode → `fontisan validate -t web`

## Why Migrate?

| Feature | fonttools | lcdf-typetools | Font-Validator | Fontisan |
|---------|-----------|----------------|----------------|----------|
| Pure Ruby | ❌ | ❌ | ❌ | ✅ |
| Font conversion | ✅ | ✅ | ❌ | ✅ |
| Validation | ❌ | ❌ | ✅ | ✅ |
| Variable fonts | ✅ | ❌ | ❌ | ✅ |
| Type 1 support | Partial | ✅ | ❌ | ✅ |
| Bidirectional hints | ❌ | Partial | ❌ | ✅ |

## Need Help?

- [GitHub Issues](https://github.com/fontist/fontisan/issues) — Report bugs or request features
- [Guide](/guide/) — Read the documentation
