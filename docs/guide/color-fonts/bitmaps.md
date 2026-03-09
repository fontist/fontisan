---
title: Bitmap Color Fonts
---

# Bitmap Color Fonts

Bitmap color fonts store pixel images at specific sizes.

## Formats

| Format | Tables | Platform |
|--------|--------|----------|
| sbix | sbix | Apple |
| CBDT/CBLC | CBDT, CBLC | Google/Android |

## sbix (Apple)

sbix stores bitmap images at multiple resolutions.

### Structure

```ruby
sbix = font.tables['sbix']

# Strikes (image sets at different sizes)
sbix.strikes.each do |strike|
  puts "Strike at #{strike.ppem} ppem"

  strike.glyphs.each do |glyph_id, image|
    puts "  Glyph #{glyph_id}: #{image.format}"
  end
end
```

### Image Formats

- `png ` — PNG image
- `jpg ` — JPEG image
- `tiff` — TIFF image
- `dupe` — Duplicate of another glyph

### Accessing Images

```ruby
sbix = font.tables['sbix']
strike = sbix.strikes.first

glyph_id = 42
image = strike.image_for(glyph_id)

puts "Format: #{image.format}"
puts "Data size: #{image.data.length} bytes"
```

## CBDT/CBLC (Android)

CBDT/CBLC stores bitmap images for Android.

### Structure

```ruby
cbdt = font.tables['CBDT']
cblc = font.tables['CBLC']

# CBLC has location data
cblc.strikes.each do |strike|
  puts "Strike at #{strike.ppem}x#{strike.ppem}"

  strike.glyph_ranges.each do |range|
    puts "  Glyphs #{range.start}..#{range.end}"
  end
end

# CBDT has actual bitmap data
```

### Bitmap Formats

- **Small metrics** — For small glyphs
- **Big metrics** — For larger glyphs
- **Bit aligned** — 1, 2, 4, or 8 bits per pixel

### Accessing Bitmaps

```ruby
cbdt = font.tables['CBDT']
cblc = font.tables['CBLC']

glyph_id = 42
strike_index = 0

# Get bitmap location
location = cblc.location(strike_index, glyph_id)

if location
  # Get bitmap data
  bitmap = cbdt.bitmap(location)
  puts "Size: #{bitmap.width}x#{bitmap.height}"
  puts "Data: #{bitmap.data.length} bytes"
end
```

## Working with Bitmaps

### List Available Sizes

```ruby
sbix = font.tables['sbix']

if sbix
  puts "Available sizes:"
  sbix.strikes.each do |strike|
    puts "  #{strike.ppem} ppem"
  end
end
```

### Export Bitmaps

```ruby
sbix = font.tables['sbix']
strike = sbix.strikes.first

sbix.glyphs.each do |glyph_id, image|
  if image.format == 'png '
    File.write("glyph-#{glyph_id}.png", image.data)
  end
end
```

## Conversion

### Preserve Bitmaps

```bash
# Bitmaps preserved during same-format conversion
fontisan convert bitmap-font.ttf --to ttf --output bitmap-font.ttf
```

### Remove Bitmaps

```bash
# Create outline-only version
fontisan convert bitmap-font.ttf --to ttf --no-bitmaps --output outline-only.ttf
```

## Comparison

| Feature | sbix | CBDT/CBLC |
|---------|------|-----------|
| Platform | Apple | Android |
| Image formats | PNG, JPEG, TIFF | Raw bitmap |
| Scalability | No | No |
| File size | Larger | Smaller |
| Quality | Photo-realistic | Limited |

## Limitations

### Bitmap Scaling

Bitmap fonts don't scale well:
- Each strike is designed for a specific ppem
- Scaling up causes pixelation
- Scaling down causes aliasing

### Variable Fonts

Bitmap fonts don't work with variation:
- No interpolation possible
- Must provide strikes for each instance

## Best Practices

1. **Provide multiple strikes** — Cover common sizes
2. **Use PNG for sbix** — Best quality/size tradeoff
3. **Test on target platforms** — Rendering varies
4. **Consider outline fallback** — For unavailable sizes
