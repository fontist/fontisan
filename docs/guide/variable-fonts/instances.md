---
title: Instance Generation
---

# Instance Generation

Generate static font instances from variable fonts at specific variation coordinates.

## CLI Usage

### Basic Instance Generation

```bash
# Generate at specific weight
fontisan instance variable.ttf --wght 700 --output bold.ttf

# Generate at specific weight and width
fontisan instance variable.ttf --wght 700 --wdth 75 --output condensed-bold.ttf

# Generate with all axes
fontisan instance variable.ttf --wght 600 --wdth 90 --slnt -12 --output custom.ttf
```

### Using Named Instances

```bash
# List available instances
fontisan instance variable.ttf --list-instances

# Generate using instance index
fontisan instance variable.ttf --named-instance 0 --output thin.ttf

# Generate using instance name
fontisan instance variable.ttf --named-instance "Bold" --output bold.ttf
```

### Output Format

```bash
# Generate as TrueType (default)
fontisan instance variable.ttf --wght 700 --output bold.ttf

# Generate as OpenType/CFF
fontisan instance variable.ttf --wght 700 --to otf --output bold.otf

# Generate as WOFF2
fontisan instance.ttf --wght 700 --to woff2 --output bold.woff2
```

## Ruby API

### Basic Generation

```ruby
require 'fontisan'

# Load variable font
font = Fontisan::FontLoader.load('variable.ttf')

# Generate instance at specific coordinates
writer = Fontisan::Variation::InstanceWriter.new(font)
instance_font = writer.generate_instance(wght: 700)

# Write to file
Fontisan::FontWriter.write(
  instance_font,
  'bold.ttf'
)
```

### Multiple Axes

```ruby
# Generate instance with multiple axis values
instance_font = writer.generate_instance(
  wght: 700,
  wdth: 75,
  slnt: -8
)
```

### Using Named Instances

```ruby
# Get named instance information
fvar = font.tables['fvar']
instance = fvar.instances[0]

# Extract coordinates from named instance
coordinates = {}
fvar.axes.each_with_index do |axis, i|
  coordinates[axis.tag] = instance.coordinates[i]
end

# Generate instance
instance_font = writer.generate_instance(coordinates)
```

## Batch Generation

### Generate All Named Instances

```ruby
font = Fontisan::FontLoader.load('variable.ttf')
fvar = font.tables['fvar']
writer = Fontisan::Variation::InstanceWriter.new(font)

fvar.instances.each do |instance|
  # Build coordinates hash
  coordinates = {}
  fvar.axes.each_with_index do |axis, i|
    coordinates[axis.tag] = instance.coordinates[i]
  end

  # Generate instance
  instance_font = writer.generate_instance(coordinates)

  # Write with instance name
  filename = instance.name.downcase.gsub(/\s+/, '-') + '.ttf'
  Fontisan::FontWriter.write(instance_font, filename)
end
```

### Generate Weight Range

```ruby
# Generate instances for common weights
weights = {
  'thin' => 100,
  'light' => 300,
  'regular' => 400,
  'medium' => 500,
  'semibold' => 600,
  'bold' => 700,
  'black' => 900
}

weights.each do |name, wght|
  instance_font = writer.generate_instance(wght: wght)
  Fontisan::FontWriter.write(instance_font, "#{name}.ttf")
end
```

## Instance Quality

### Coordinate Validation

Coordinates must be within axis ranges:

```ruby
fvar = font.tables['fvar']

fvar.axes.each do |axis|
  min = axis.min_value
  max = axis.max_value

  if value < min || value > max
    raise "Value #{value} out of range for #{axis.tag}"
  end
end
```

### Default Values

When an axis is not specified, the default value is used:

```ruby
# If wght is not specified, uses default from fvar
instance_font = writer.generate_instance(wdth: 75)
```

## Performance

### Caching

Fontisan caches intermediate computations for faster instance generation:

```ruby
# Create writer once
writer = Fontisan::Variation::InstanceWriter.new(font)

# Generate multiple instances efficiently
(100..900).step(100).each do |wght|
  instance_font = writer.generate_instance(wght: wght)
  # ...
end
```
