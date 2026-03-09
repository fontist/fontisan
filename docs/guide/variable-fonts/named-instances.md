---
title: Named Instances
---

# Named Instances

Work with named instances in variable fonts.

## Overview

Named instances are predefined points in the design space with specific names. They provide:
- User-friendly names for common variations
- Consistent styling across applications
- Easy access to frequently used configurations

## Listing Named Instances

### CLI

```bash
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

### API

```ruby
font = Fontisan::FontLoader.load('variable.ttf')
fvar = font.tables['fvar']

fvar.instances.each_with_index do |instance, index|
  puts "#{index}: #{instance.name}"
  instance.coordinates.each do |tag, value|
    puts "  #{tag} = #{value}"
  end
end
```

## Instance Properties

| Property | Description |
|----------|-------------|
| `name` | Human-readable instance name |
| `coordinates` | Hash of axis tag → value |

## Generating Named Instances

### By Index

```bash
# Generate first named instance
fontisan instance variable.ttf --named-instance 0 --output thin.ttf

# Generate third named instance
fontisan instance variable.ttf --named-instance 2 --output regular.ttf
```

### By Name

```bash
# Generate by name
fontisan instance variable.ttf --named-instance "Bold" --output bold.ttf
```

### API

```ruby
font = Fontisan::FontLoader.load('variable.ttf')
fvar = font.tables['fvar']
writer = Fontisan::Variation::InstanceWriter.new(font)

# Find instance by name
bold_instance = fvar.instances.find { |i| i.name == "Bold" }

if bold_instance
  # Build coordinates hash
  coordinates = {}
  fvar.axes.each_with_index do |axis, i|
    coordinates[axis.tag] = bold_instance.coordinates[i]
  end

  # Generate instance
  bold_font = writer.generate_instance(coordinates)
  Fontisan::FontWriter.write(bold_font, 'bold.ttf')
end
```

## Generating All Named Instances

```ruby
font = Fontisan::FontLoader.load('variable.ttf')
fvar = font.tables['fvar']
writer = Fontisan::Variation::InstanceWriter.new(font)

fvar.instances.each do |instance|
  # Build coordinates
  coordinates = {}
  fvar.axes.each_with_index do |axis, i|
    coordinates[axis.tag] = instance.coordinates[i]
  end

  # Generate instance
  instance_font = writer.generate_instance(coordinates)

  # Create safe filename
  filename = instance.name.downcase.gsub(/[^a-z0-9]+, '-') + '.ttf'

  Fontisan::FontWriter.write(instance_font, filename)
  puts "Generated: #{filename}"
end
```

## Instance Names

Instance names follow conventions:

### Weight-Based

- Thin
- Extra Light
- Light
- Regular
- Medium
- Semi Bold
- Bold
- Extra Bold
- Black

### Width-Based

- Ultra Condensed
- Extra Condensed
- Condensed
- Semi Condensed
- Normal
- Semi Expanded
- Expanded
- Extra Expanded
- Ultra Expanded

### Combinations

- Condensed Bold
- Expanded Light
- Semi Condensed Medium

## STAT Table

The STAT table provides additional instance information:

```ruby
stat = font.tables['STAT']

if stat
  stat.axis_values.each do |axis_value|
    puts "#{axis_value.name}"
    puts "  Axis: #{axis_value.axis_tag}"
    puts "  Value: #{axis_value.value}"
    puts "  Linked: #{axis_value.linked_value}" if axis_value.linked_value
  end
end
```

## Instance Validation

Validate instances before generation:

```ruby
fvar = font.tables['fvar']

fvar.instances.each do |instance|
  valid = true

  fvar.axes.each_with_index do |axis, i|
    value = instance.coordinates[i]
    if value < axis.min_value || value > axis.max_value
      puts "Warning: #{instance.name} has #{axis.tag}=#{value} out of range"
      valid = false
    end
  end

  if valid
    puts "#{instance.name}: Valid"
  end
end
```
