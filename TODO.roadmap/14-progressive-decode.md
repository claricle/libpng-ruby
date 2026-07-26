# 14 - Progressive/streaming decode

- **Priority**: Skip
- **Status**: Won't do

## Context

libpng supports progressive (streaming) decode via
`png_set_progressive_read_fn` + `png_process_data`. This lets callers
feed bytes incrementally as they arrive (e.g. over a network socket)
rather than buffering the entire PNG first.

## Why we won't do this

1. **No use case yet**: The gem's consumers (emfsvg, image processing
   tools) work with complete PNGs in memory.

2. **API complexity**: Progressive decode requires a stateful reader
   object (`Libpng::ProgressiveReader`?) with `#feed(bytes)` and
   `#finish` methods, plus callback hooks for row completion. This is
   a significantly different API surface from the current
   `Libpng.decode(png_bytes)`.

3. **Ruby I/O is usually buffered anyway**: Ruby's `IO.read`,
   `Net::HTTP.get`, etc. all return complete strings. Streaming is the
   exception, not the rule.

4. **Memory savings are minimal**: A typical PNG is 100KB-5MB.
   Buffering the whole thing in a String is fine for almost all use
   cases.

## When this position might change

- A user building a streaming image service (e.g. progressive JPEG-like
  loading for web).
- A request from a framework like Rack that wants to decode PNG
  uploads as they arrive.

## Alternative if needed

Use a tempfile + standard `Libpng.decode`:
```ruby
File.open(upload_path, 'wb') { |f| f.write(chunk) until done }
decoded = Libpng.decode(File.binread(upload_path))
```

Not streaming, but avoids holding the entire upload in Ruby memory.
