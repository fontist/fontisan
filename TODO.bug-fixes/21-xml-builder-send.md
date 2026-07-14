# 21 — XML builder send() → tag!

## Priority
P2

## Problem
3 `xml.send(tag.to_sym)` calls in export/ use `.send` to create XML
elements with dynamic tag names. This violates the "no private send"
rule even though it's a common Ruby XML builder pattern.

## Sites
- `lib/fontisan/models/ttx/tables/binary_table.rb:21` `xml.send(tag.to_sym)`
- `lib/fontisan/export/ttx_generator.rb:297` `xml.send(tag.to_sym)`
- `lib/fontisan/export/ttx_generator.rb:313` `xml.send(clean_tag.to_sym)`

## Approach
Replace `xml.send(tag.to_sym) { ... }` with `xml.tag!(tag) { ... }`
(or the Builder-native equivalent public method). Builder::XmlMarkup
and Nokogiri::XML::Builder both expose `tag!` as the public dynamic
element creator.

## Acceptance criteria
- 0 `send(` in `lib/fontisan/export/` and `lib/fontisan/models/ttx/`
- All export/ttx specs pass
