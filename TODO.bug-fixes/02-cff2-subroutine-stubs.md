# 02 — CFF2 subroutine call stubs

## Priority
P0

## Problem
`Tables::Cff2::CharstringParser#callsubr` and `callgsubr`
(charstring_parser.rb:577-595) clear the operand stack instead of
executing the referenced subroutine.

CFF2 fonts that use subroutines for file size optimization (very
common) will have **incomplete charstring interpretation** — outlines
encoded via subroutines are silently dropped.

## Goal
Implement `callsubr` and `callgsubr` per the CFF2 spec:
1. Calculate subroutine bias from INDEX count
2. Resolve actual subroutine index: `popped_value + bias`
3. Get subroutine bytecode from the Local/Global Subr INDEX
4. Recursively parse the subroutine bytecode (pushing/popping
   operands across the call boundary)

## Approach
- Add `local_subr_bias` and `global_subr_bias` computed from INDEX sizes
- `callsubr`: resolve via local subrs INDEX + bias
- `callgsubr`: resolve via global subrs INDEX + bias
- Both: recursively call `parse_charstring_bytes` on the subroutine data

## Acceptance criteria
- callsubr correctly calls a local subroutine with bias
- callgsubr correctly calls a global subroutine with bias
- Spec covers a charstring with subroutine calls
