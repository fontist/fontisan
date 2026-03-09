---
title: Apple dfont
---

# Apple dfont

Apple Data Fork Font (dfont) is a legacy Mac OS X format.

## Overview

- **Container**: Resource fork format in data fork
- **Font Types**: TrueType, OpenType, or mixed
- **Platform**: macOS specific

## Structure

dfont uses resource fork structure:
- Resource map
- Resource data
- Multiple font resources

## Loading

```ruby
font = Fontisan::FontLoader.load('font.dfont')

# Access as collection
if font.respond_to?(:each)
  font.each do |f|
    puts "#{f.family_name} #{f.style}"
  end
end
```

## Extracting

### CLI

```bash
# List fonts in dfont
fontisan ls font.dfont

# Extract all
fontisan unpack font.dfont --output-dir ./extracted
```

### API

```ruby
dfont = Fontisan::FontLoader.load('font.dfont')

dfont.each_with_index do |font, index|
  output = "font-#{index}.ttf"
  Fontisan::FontWriter.write(font, output)
end
```

## Converting

### dfont to TTF

```bash
fontisan convert font.dfont --to ttf --output font.ttf
```

### dfont to OTF

```bash
fontisan convert font.dfont --to otf --output font.otf
```

### To dfont

```bash
# From TTC
fontisan convert family.ttc --to dfont --output family.dfont

# From individual fonts
fontisan pack regular.ttf bold.ttf --output family.dfont
```

## Limitations

- **macOS only** — Not cross-platform
- **Legacy format** — Modern formats preferred
- **Limited support** — Some tools don't read dfont

## When to Use

- **Legacy Mac fonts** — Converting old resources
- **Resource fork recovery** — Extracting embedded fonts
- **macOS compatibility** — When required

## Modern Alternatives

For new fonts, prefer:
- **TTC** — TrueType Collection
- **OTC** — OpenType Collection
- **WOFF2** — Web delivery
