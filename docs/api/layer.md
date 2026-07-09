---
title: Ufo::Layer
---

# `Ufo::Layer`

A single layer in a UFO source. A `Layer` holds a set of glyphs keyed by name. The default layer is `public.default` per UFO 3.

```ruby
layer = Fontisan::Ufo::Layer.new                       # => "public.default"
layer.add(Fontisan::Ufo::Glyph.new(name: "A"))
layer["A"]                                             # => the glyph
layer.size                                             # => 1
```

## Naming contract

Glyph names are the layer's primary key. Two distinct glyphs with the same name cannot coexist — adding the second would silently destroy the first, a class of bug that has historically cost real data (e.g. the CJK Ext G cmap loss when CBDT placeholders collided with outline glyphs sharing `"gid{N}"` names).

To make that contract unbreakable, the API exposes two methods with named semantics:

| Method | Behavior on conflict |
|--------|----------------------|
| `Layer#add(glyph)` | **Raises** `Ufo::GlyphExistsError` (the safe default) |
| `Layer#put(glyph)` | Overwrites the existing glyph (explicit replace) |

Callers that need auto-renaming — insert without giving up on a collision — call `Stitcher::UniqueGlyphName.in(target, base)` first to allocate a free name, then `Layer#add` the glyph under that name.

## API

### `Layer.new(name = "public.default")`

Initialize an empty layer.

### `#add(glyph) -> Glyph`

Insert `glyph`. Raises `Ufo::GlyphExistsError` if a glyph with the same name is already present.

```ruby
layer = Fontisan::Ufo::Layer.new
layer.add(Fontisan::Ufo::Glyph.new(name: "A"))

layer.add(Fontisan::Ufo::Glyph.new(name: "A"))
# => raises Fontisan::Ufo::GlyphExistsError: a glyph named "A" already exists
```

The original glyph is preserved when the second `add` raises — the layer is never partially mutated.

### `#put(glyph) -> Glyph`

Insert `glyph`, replacing any existing glyph with the same name. Use this when the caller has positively decided the previous glyph (if any) should be discarded.

```ruby
layer.put(Fontisan::Ufo::Glyph.new(name: "A"))  # overwrites the prior "A"
```

### `#[](glyph_name) -> Glyph, nil`

Look up a glyph by name.

### `#each { |glyph| ... }`

Iterate over glyphs (no ordering guarantee).

### `#size -> Integer`

Number of glyphs in the layer.

## `Ufo::GlyphExistsError`

Raised by `Layer#add` on a name conflict. Carries the colliding name so callers can branch programmatically:

```ruby
begin
  layer.add(glyph)
rescue Fontisan::Ufo::GlyphExistsError => e
  puts "name #{e.name.inspect} already taken"
  # Decide: layer.put(glyph) to overwrite, or
  # unique = Fontisan::Stitcher::UniqueGlyphName.in(target, e.name)
  # layer.add(glyph.dup_as(name: unique))
end
```

The error class is a sibling of `Layer` (not nested inside it) so the namespace stays flat — both `Ufo::Layer` and `Ufo::GlyphExistsError` live directly under `Fontisan::Ufo`.

## See also

- `docs/STITCHER_GUIDE.adoc` — `UniqueGlyphName`, `GlyphCopier`, and `CbdtPropagator` all build on the Layer naming contract.
- `docs/UFO_COMPILATION.adoc` — how layers feed the TTF/OTF/CFF2 compilers.
