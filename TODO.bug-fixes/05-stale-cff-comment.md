# 05 — Stale CFF comment

## Priority
P2

## Problem
`lib/fontisan/tables/cff.rb:113` says:
"Additional structures (CharStrings, Charset, Encoding, Private DICT)
will be implemented in follow-up tasks."

These structures ARE all implemented (charstrings_index, charset,
encoding, private_dict methods exist and work). The comment is stale.

## Goal
Remove or update the stale comment.

## Acceptance criteria
- Comment accurately reflects current state
