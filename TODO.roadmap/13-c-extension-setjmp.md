# 13 - C extension wrapper for setjmp

- **Priority**: Skip
- **Status**: Won't do

## Context

`encode_standard` uses `png_set_error_fn` to register an FFI callback
that calls `rb_raise` instead of libpng's default `abort()`. libpng
expects error callbacks to `longjmp` back to a `setjmp` point set up
by the caller. Calling `rb_raise` from the FFI callback unwinds the
Ruby stack via Ruby's own `longjmp`-based exception machinery.

This works for input-validation errors (most cases) but has a subtle
caveat: libpng's internal state between the callback invocation and
the `setjmp` target is not cleaned up. Our `ensure` block calls
`png_destroy_write_struct` to release the C state, which is sufficient
in practice.

## Why we won't do this

A C extension could properly wrap the standard API with `setjmp`:
```c
if (setjmp(png_jmpbuf(png_ptr))) {
    /* longjmp target -- copy error message, return error code */
}
```

This would give clean error handling without Ruby stack unwinding
concerns.

But:

1. **Adds a build dependency**: A C extension means the gem requires a
   C compiler at install time on every platform. We currently ship
   pre-compiled binary gems for 9 platforms specifically to avoid
   this. Adding a C extension would require shipping pre-compiled
   extensions for each platform too -- a significant build/release
   burden.

2. **Current approach works**: The rb_raise-from-callback pattern has
   not caused any user-visible issues in testing or production use.

3. **Documented in README**: The caveat is called out in the
   `encode_standard` documentation. Users who need bulletproof error
   handling for adversarial input can validate before calling.

4. **Simplified API already handles it cleanly**: The `png_image_*`
   API uses an internal `setjmp` and captures errors into the message
   buffer. For decode paths (where adversarial input is most likely),
   `Libpng.decode` is the right choice.

## When this position might change

- A real-world crash report attributed to the rb_raise-from-callback
  pattern.
- A user needing to call `encode_standard` in a tight loop with
  potentially-corrupt pixel buffers (where the half-freed png_struct
  could accumulate state).

## Alternative under consideration

If we ever do add a C extension, it would be a tiny `.c` file (maybe
50 lines) exposing a single function:

```c
int libpng_encode_to_memory_safe(
    uint32_t width, uint32_t height, int bit_depth, int color_type,
    int interlace, int filter, int compression_level,
    const void *pixels, int stride,
    const void *palette, int palette_entries,
    void **out, size_t *out_len,
    char *err_msg, size_t err_msg_len);
```

This would be the only C function in the gem. FFI would bind it
directly. All libpng state would be confined inside the C function.
