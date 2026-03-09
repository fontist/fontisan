---
title: OutlineConverter
---

# OutlineConverter

Convert font outlines between formats.

## Overview

`Fontisan::Converters::OutlineConverter` handles TTF ↔ OTF conversion.

## Methods

### convert(font, options: nil)

Convert a font to a different format.

```ruby
converter = Fontisan::Converters::OutlineConverter.new
options = Fontisan::ConversionOptions.recommended(from: :ttf, to: :otf)
result = converter.convert(font, options: options)
```

## See Also

- [ConversionOptions](/api/conversion-options)
