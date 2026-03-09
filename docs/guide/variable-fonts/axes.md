---
title: Axes and Instances
---

# Axes and Instances

Work with variation axes and named instances in variable fonts.

## Getting Axis Information

### CLI

```bash
# Show axis information
fontisan info variable.ttf

# Example output:
# Variable Font Axes: 2
#   wght (Weight): 100 - 900, default: 400
#   wdth (Width): 75 - 125, default: 100
```

### API

```ruby
font = Fontisan::FontLoader.load('variable.ttf')
fvar = font.tables['fvar']

# List axes
fvar.axes.each do |axis|
  puts "Tag: #{axis.tag}"
  puts "  Min: #{axis.min_value}"
  puts "  Max: #{axis.max_value}"
  puts "  Default: #{axis.default_value}"
  puts "  Name: #{axis.name}"
end
```

## Axis Properties

Each axis has these properties:

| Property | Description |
|----------|-------------|
| `tag` | Four-character axis identifier (e.g., `wght`) |
| `min_value` | Minimum value on the axis |
| `max_value` | Maximum value on the axis |
| `default_value` | Default value when no variation applied |
| `name` | Human-readable axis name |

## Registered Axes

### Weight (`wght`)

Controls font weight.

```ruby
# Range: typically 100-900
# Common values:
# 100 - Thin
# 200 - Extra Light
# 300 - Light
# 400 - Regular
# 500 - Medium
# 600 - Semi Bold
# 700 - Bold
# 800 - Extra Bold
# 900 - Black
```

### Width (`wdth`)

Controls font width.

```ruby
# Range: typically 50-200 (percentage)
# Common values:
# 50  - Ultra Condensed
# 62.5 - Extra Condensed
# 75  - Condensed
# 87.5 - Semi Condensed
# 100 - Normal
# 112.5 - Semi Expanded
# 125 - Expanded
# 150 - Extra Expanded
# 200 - Ultra Expanded
```

### Slant (`slnt`)

Controls slant angle.

```ruby
# Range: -90 to 90 degrees
# Common values:
# 0   - Upright
# -12 - Typical italic slant
```

### Italic (`ital`)

Binary italic toggle.

```ruby
# Range: 0-1
# 0 - Roman (upright)
# 1 - Italic
```

### Optical Size (`opsz`)

Controls optical sizing.

```ruby
# Range: varies by font
# Example values:
# 8   - Caption
# 12  - Text
# 24  - Subhead
# 72  - Display
```

## Named Instances

### List Named Instances

```bash
# CLI
fontisan instance variable.ttf --list-instances

# Example output:
# Named Instances: 6
#   0: Thin (wght=100)
#   1: Light (wght=300)
#   2: Regular (wght=400)
#   3: Medium (wght=500)
#   4: Bold (wght=700)
#   5: Black (wght=900)
```

### API Access

```ruby
font = Fontisan::FontLoader.load('variable.ttf')
fvar = font.tables['fvar']

# List named instances
fvar.instances.each_with_index do |instance, index|
  puts "#{index}: #{instance.name}"
  instance.coordinates.each do |tag, value|
    puts "  #{tag} = #{value}"
  end
end
```

## Using Named Instances

### CLI

```bash
# Generate using instance index
fontisan instance variable.ttf --named-instance 0 --output thin.ttf

# Generate using instance name
fontisan instance variable.ttf --named-instance "Bold" --output bold.ttf
```

### API

```ruby
# Get named instance coordinates
fvar = font.tables['fvar']
instance = fvar.instances.find { |i| i.name == "Bold" }

# Generate instance with those coordinates
writer = Fontisan::Variation::InstanceWriter.new(font)
bold_font = writer.generate_instance(instance.coordinates)
```

## avar Table

The avar (Axis Variation) table defines non-linear axis value mappings.

```ruby
# Check for avar table
avar = font.tables['avar']

if avar
  puts "Non-linear interpolation present"
  avar.mappings.each do |tag, map|
    puts "#{tag}: #{map}"
  end
end
```

## STAT Table

The STAT (Style Attributes) table provides style attributes and axis value names.

```ruby
stat = font.tables['STAT']

if stat
  # Get axis values
  stat.axis_values.each do |axis_value|
    puts "#{axis_value.name}: #{axis_value.value}"
  end
end
```
