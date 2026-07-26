# frozen_string_literal: true

require 'ffi'

module Libpng
  # FFI bindings to the bundled `libpng16.{so,dylib,dll}`. Lives in its
  # own autoloaded module so that requiring `libpng` (the top-level
  # entry point used by `ext/extconf.rb` during the source-gem build)
  # does NOT eagerly dlopen the shared library -- it may not exist yet
  # at that point.
  #
  # The first time an encoder or decoder references `Libpng::Binding`,
  # this file loads, ffi_lib fires, and the FFI functions attach. From
  # then on, calls go directly through the attached C functions.
  module Binding
    extend FFI::Library

    ffi_lib_flags :now, :global

    lib_filename = if FFI::Platform.windows?
                     'libpng16.dll'
                   elsif FFI::Platform.mac?
                     'libpng16.dylib'
                   else
                     'libpng16.so'
                   end

    # __dir__ is lib/libpng/; the shared library ships at lib/libpng/.
    ffi_lib File.expand_path(lib_filename, __dir__)

    # libpng simplified API (png_image / png_image_*).
    attach_function :png_image_begin_read_from_memory,
                    %i[pointer pointer size_t], :int
    attach_function :png_image_finish_read,
                    %i[pointer pointer pointer int pointer], :int
    attach_function :png_image_write_to_memory,
                    %i[pointer pointer pointer int pointer int pointer], :int
    attach_function :png_image_free, [:pointer], :void

    # libpng standard (non-simplified) write API.
    attach_function :png_create_write_struct,
                    %i[string pointer pointer pointer], :pointer
    attach_function :png_create_info_struct, [:pointer], :pointer
    attach_function :png_destroy_write_struct, %i[pointer pointer], :void
    attach_function :png_set_IHDR,
                    %i[pointer pointer uint32 uint32 int int int int int], :void
    attach_function :png_set_rows, %i[pointer pointer pointer], :void
    attach_function :png_set_PLTE, %i[pointer pointer pointer int], :void
    attach_function :png_set_tRNS,
                    %i[pointer pointer pointer int pointer], :void
    attach_function :png_set_filter, %i[pointer int int], :void
    attach_function :png_set_compression_level, %i[pointer int], :void
    attach_function :png_set_write_fn,
                    %i[pointer pointer pointer pointer], :void
    attach_function :png_write_png, %i[pointer pointer int pointer], :void
  end
end
