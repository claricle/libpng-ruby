# frozen_string_literal: true

module Libpng
  # One user-supplied text entry, normalized. The encoder decides
  # whether to emit it as tEXt (Latin-1 ASCII) or iTXt (UTF-8 with
  # potentially multibyte characters) based on whether the value
  # contains non-ASCII bytes.
  TextEntry = Struct.new(:key, :value, keyword_init: true) do
    def compression
      value.ascii_only? ? TEXT_COMPRESSION_NONE : TEXT_COMPRESSION_ITXT_KEY
    end
  end

  # Writes an Array of TextEntry as a png_text array via png_set_text.
  # All FFI allocations live inside the block; strings must outlive
  # the png_set_text call, which copies their bytes into libpng's
  # internal storage.
  #
  # The png_text struct layout is computed dynamically via
  # FFI.type_size so the code is portable across 32-bit and 64-bit
  # builds (though the gem currently only ships 64-bit binaries).
  module TextWriter
    module_function

    def call(png_ptr, info_ptr, entries)
      return if entries.empty?

      struct_size = text_struct_size
      FFI::MemoryPointer.new(:uint8, struct_size * entries.length) do |array|
        entries.each_with_index do |entry, i|
          populate_entry(array + (i * struct_size), entry)
        end
        Libpng::Binding.png_set_text(png_ptr, info_ptr, array, entries.length)
      end
    end

    # png_text struct layout (computed once):
    #   int   compression   (offset 0)
    #   char* key           (after alignment)
    #   char* text
    #   size_t text_length
    #   size_t itxt_length
    #   char* lang
    #   char* lang_key
    def text_struct_size
      int_size = FFI.type_size(:int)
      ptr_size = FFI.type_size(:pointer)
      sz_size = FFI.type_size(:size_t)
      natural = ptr_size # both pointer and size_t align to pointer width
      offset = align_up(int_size, natural)
      2.times { offset += ptr_size } # key, text
      2.times { offset += sz_size }  # text_length, itxt_length
      2.times { offset += ptr_size } # lang, lang_key
      align_up(offset, natural) # round up to natural struct alignment
    end

    def populate_entry(slot, entry)
      int_size = FFI.type_size(:int)
      ptr_size = FFI.type_size(:pointer)
      sz_size = FFI.type_size(:size_t)
      natural = ptr_size

      slot.put_int(0, entry.compression)

      # Allocate persistent C strings for key, text. These must
      # outlive png_set_text; once that returns libpng has copied
      # the bytes internally.
      key_bytes = "#{entry.key.b}\x00"
      val_bytes = "#{entry.value.b}\x00"
      key_ptr = FFI::MemoryPointer.new(:uint8, key_bytes.bytesize, false)
      key_ptr.write_bytes(key_bytes)
      val_ptr = FFI::MemoryPointer.new(:uint8, val_bytes.bytesize, false)
      val_ptr.write_bytes(val_bytes)

      offset = align_up(int_size, natural)
      slot.put_pointer(offset, key_ptr)
      offset += ptr_size
      slot.put_pointer(offset, val_ptr)
      offset += ptr_size
      put_size(slot, offset, entry.value.bytesize)
      offset += sz_size
      itxt_len = entry.value.ascii_only? ? 0 : entry.value.bytesize
      put_size(slot, offset, itxt_len)
      offset += sz_size
      slot.put_pointer(offset, nil)
      offset += ptr_size
      slot.put_pointer(offset, nil)
    end

    # Write a size_t value to a slot at the given offset. FFI doesn't
    # expose put_size_t directly; choose the right writer based on the
    # platform's size_t width (8 bytes on 64-bit, 4 on 32-bit).
    def put_size(slot, offset, value)
      if FFI.type_size(:size_t) == 8
        slot.put_uint64(offset, value)
      else
        slot.put_uint32(offset, value)
      end
    end

    def align_up(value, alignment)
      ((value + alignment - 1) / alignment) * alignment
    end
  end
end
