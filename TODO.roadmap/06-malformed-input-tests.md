# 06 - Malformed input tests for decode

- **Priority**: P1
- **Status**: Done

## Context

The original spec covered "non-PNG input" and "truncated input" but
not:
- Empty / nil input
- Corrupt IHDR CRC
- Corrupt IDAT CRC
- Zero-dimension IHDR
- Impossibly large dimensions
- PNG missing IEND
- PNG truncated mid-IDAT

libpng's simplified read API is well-behaved on bad input (captures
errors into the `png_image` message buffer instead of aborting), but
the wrapper should still raise `Libpng::Error` rather than propagate
`NoMethodError` or segfault.

## Approach

New spec file `spec/malformed_input_spec.rb`. Each case constructs a
broken PNG and asserts that `Libpng.decode` raises `Libpng::Error`
(or, for borderline cases, doesn't crash).

Helper methods on the spec:
- `with_chunk(png, type, replacement_data)` -- splice replacement data
  into a specific chunk
- `corrupt_crc(png, type)` -- XOR the first CRC byte of a chunk

## What we learned

- `nil` input previously raised `NoMethodError: undefined method
  'bytesize' for nil`. Fixed by adding a nil guard in
  `Libpng::SimplifiedDecoder#initialize`.
- Zero-dimension IHDR detection works (libpng rejects).
- Corrupt IHDR CRC is detected by libpng and raises cleanly.
- Corrupt IDAT CRC: libpng's simplified API may either error or
  accept (zlib is sometimes able to decode despite the bad CRC). The
  spec tolerates both outcomes.

## Delivered

PR #7 (this branch).
