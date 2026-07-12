# 06 — Variable font instance WOFF2 output

## Priority
P1

## Problem
`Variation::InstanceWriter` raises `Fontisan::Error` for WOFF2 output
instead of writing the file. Variable font instances can be written
to TTF, OTF, and WOFF but not WOFF2.

## Goal
Wire the existing WOFF2 encoder into the instance writer so
`write(format: :woff2)` produces a valid WOFF2 file.

## Approach
The instance writer already calls `write_sfnt` for TTF/OTF and
`write_woff` for WOFF. Add a `write_woff2` method that:
1. Writes the SFNT tables to a temp TTF
2. Loads the temp TTF
3. Encodes to WOFF2 via `Converters::FormatConverter`

## Acceptance criteria
- `instance_writer.write(format: :woff2)` produces a valid WOFF2 file
- The WOFF2 file decodes back to the correct instance tables
