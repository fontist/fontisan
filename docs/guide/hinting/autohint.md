---
title: Autohint
---

# Autohint

Fontisan supports automatic hint generation for fonts without hints or when converting between formats.

## Overview

Autohinting generates hint data automatically based on glyph outlines. This is useful when:

- Source font lacks hints
- Converting between incompatible hint systems
- Improving rendering quality

## CLI Usage

```bash
# Enable autohinting during conversion
fontisan convert font.ttf --to otf --autohint --output font.otf

# With specific hinting mode
fontisan convert font.ttf --to otf --autohint --hinting-mode auto
```

## API Usage

```ruby
options = Fontisan::ConversionOptions.new(
  opening: { autohint: true },
  generating: { hinting_mode: "auto" }
)

converter = Fontisan::Converters::OutlineConverter.new
result = converter.convert(font, options: options)
```

## Hinting Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `preserve` | Keep original hints | Same-format conversions |
| `auto` | Apply automatic hinting | Cross-format, missing hints |
| `none` | Remove all hints | Smallest file size |
| `full` | Full hint conversion | Maximum quality |

## When to Use Autohint

### Use Autohint When:

- Converting TTF to OTF (different hint systems)
- Converting OTF to TTF (different hint systems)
- Source font has no hints
- Source hints are corrupt or incomplete

### Don't Use Autohint When:

- Converting same format (TTF → TTF, OTF → OTF)
- Source has good TrueType instructions
- Source has good PostScript hints
- Target application doesn't use hints

## Autohint Process

### For TrueType Output

1. Analyze glyph outlines
2. Detect stem widths and positions
3. Generate CVT table with common values
4. Create prep program with basic setup
5. Leave fpgm empty (no glyph programs)

### For OpenType Output

1. Analyze glyph outlines
2. Detect blue zones (baseline, x-height, cap height)
3. Detect stem widths
4. Generate Private DICT parameters
5. Create stem hints in CharStrings

## Quality

### Autohint Limitations

- **No glyph-specific instructions** — Only global hints
- **May not match hand-tuned hints** — Quality varies
- **Better than no hints** — Generally improves rendering

### Comparison

| Source | Autohint | Hand-Tuned |
|--------|----------|------------|
| Quality | Good | Best |
| Consistency | High | Varies |
| Time | Fast | Slow |
| Cost | Free | Expensive |

## Examples

### Convert with Autohint

```bash
# Type 1 to OTF with autohint
fontisan convert font.pfb --to otf --autohint --output font.otf
```

### Remove and Regenerate Hints

```bash
# Remove existing hints, add autohints
fontisan convert font.ttf --to ttf --hinting-mode none --autohint --output font-rehinted.ttf
```

### Batch Processing

```ruby
Dir.glob('fonts/*.ttf').each do |input|
  output = input.sub('.ttf', '-hinted.ttf')
  options = Fontisan::ConversionOptions.new(
    opening: { autohint: true },
    generating: { hinting_mode: "auto" }
  )

  font = Fontisan::FontLoader.load(input)
  converter = Fontisan::Converters::OutlineConverter.new
  result = converter.convert(font, options: options)
  Fontisan::FontWriter.write(result, output)
end
```

## Testing Hints

After autohinting, test rendering quality:

```bash
# Generate sample images at small sizes
fontisan render font-hinted.ttf --size 8 --output sample-8pt.png
fontisan render font-hinted.ttf --size 10 --output sample-10pt.png
fontisan render font-hinted.ttf --size 12 --output sample-12pt.png
```
