---
title: HintConverter
---

# HintConverter

Convert hints between TrueType and PostScript formats.

## Overview

`Fontisan::Converters::HintConverter` handles bidirectional hint conversion.

## Methods

### truetype_to_postscript(font)

Convert TrueType instructions to PostScript hints.

```ruby
converter = Fontisan::Converters::HintConverter.new
ps_hints = converter.truetype_to_postscript(font)
```

### postscript_to_truetype(font)

Convert PostScript hints to TrueType instructions.

```ruby
ttf_tables = converter.postscript_to_truetype(font)
```

## See Also

- [Font Hinting Guide](/guide/hinting/)
