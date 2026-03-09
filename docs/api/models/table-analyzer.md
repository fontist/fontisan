---
title: TableAnalyzer
---

# TableAnalyzer

Font table analysis.

## Overview

`Fontisan::TableAnalyzer` analyzes font tables.

## Methods

### analyze(fonts, parallel: false)

Analyze fonts for table sharing.

```ruby
analyzer = Fontisan::TableAnalyzer.new(fonts, parallel: true)
stats = analyzer.analyze
puts "Shared tables: #{stats.shared_count}"
```

### checksum(table)

Calculate table checksum.

```ruby
checksum = analyzer.checksum(font.tables['head'])
```

## See Also

- [Collections Guide](/guide/formats/collections)
