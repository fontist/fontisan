---
title: TrueType Hinting
---

# TrueType Hinting

TrueType hinting uses bytecode instructions to control glyph rendering.

## Storage

TrueType hints are stored in three tables:

| Table | Purpose |
|-------|---------|
| `prep` | Control Value Program |
| `fpgm` | Font Program |
| `cvt` | Control Value Table |

## Instructions

### Stack Operations

| Opcode | Name | Purpose |
|--------|------|---------|
| `0x40` | NPUSHB | Push n bytes onto stack |
| `0x41` | NPUSHW | Push n words onto stack |
| `0xB0-0xB7` | PUSHB[0-7] | Push 1-8 bytes |
| `0xB8-0xBF` | PUSHW[0-7] | Push 1-8 words |

### Control Value Instructions

| Opcode | Name | Purpose |
|--------|------|---------|
| `0x1D` | SCVTCI | Set CVT cut-in |
| `0x1E` | SSWCI | Set single width cut-in |
| `0x1F` | SSW | Set single width |
| `0x44` | WCVTP | Write CVT in pixels |
| `0x70` | WCVTF | Write CVT in FUnits |

## Reading Instructions

```ruby
font = Fontisan::FontLoader.load('font.ttf')

# Get prep table
prep = font.tables['prep']
if prep
  puts "Prep program: #{prep.bytecode.length} bytes"

  # Parse instructions
  parser = Fontisan::Hints::InstructionParser.new
  instructions = parser.parse(prep.bytecode)

  instructions.each do |inst|
    puts "#{inst.opcode.to_s(16)}: #{inst.name}"
  end
end

# Get CVT table
cvt = font.tables['cvt']
if cvt
  puts "CVT entries: #{cvt.values.length}"
  cvt.values.each_with_index do |value, i|
    puts "  CVT[#{i}] = #{value}"
  end
end
```

## Validation

```ruby
validator = Fontisan::Hints::HintValidator.new

# Validate prep instructions
prep = font.tables['prep']
result = validator.validate_truetype_instructions(prep.bytecode)

if result[:valid]
  puts "Valid instructions"
else
  result[:errors].each do |error|
    puts "Error: #{error}"
  end
end
```

### Validation Checks

- **Bytecode Structure** — Validates instruction opcodes and parameters
- **Stack Operations** — Ensures proper stack depth management
- **Parameter Counts** — Verifies correct number of operands
- **Truncation Detection** — Identifies incomplete instructions
- **Stack Neutrality** — Checks if sequences maintain stack balance

## Instruction Encoding

The generator automatically selects efficient encoding:

### Byte Values (0-255)

```
Value 17: PUSHB[0] 17          (2 bytes)
Values [10,20,30]: NPUSHB 3 10 20 30  (5 bytes)
```

### Word Values (256-65535)

```
Value 300: PUSHW[0] 0x01 0x2C   (3 bytes, big-endian)
Values [300,400]: NPUSHW 2 0x01 0x2C 0x01 0x90  (7 bytes)
```

## CVT Values

The Control Value Table stores frequently used values:

```ruby
cvt = font.tables['cvt']

# Typical CVT layout
# CVT[0] - Standard vertical stem width
# CVT[1] - Standard horizontal stem width
# CVT[2-7] - Blue zone values
# CVT[8+] - Other common values

puts "Standard V stem: #{cvt.values[0]}"
puts "Standard H stem: #{cvt.values[1]}"
```

## Best Practices

1. **Use CVT for common values** — Reduces bytecode size
2. **Keep prep simple** — Complex programs can cause compatibility issues
3. **Test cross-platform** — Hinting behavior varies by rasterizer
4. **Validate before release** — Ensure instructions are well-formed
