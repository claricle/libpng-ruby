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

    # ----------------------------------------------------------------
    # libpng simplified API (png_image / png_image_*).
    # ----------------------------------------------------------------
    attach_function :png_image_begin_read_from_memory,
                    %i[pointer pointer size_t], :int
    attach_function :png_image_finish_read,
                    %i[pointer pointer pointer int pointer], :int
    attach_function :png_image_write_to_memory,
                    %i[pointer pointer pointer int pointer int pointer], :int
    attach_function :png_image_free, [:pointer], :void

    # ----------------------------------------------------------------
    # libpng standard write API.
    # ----------------------------------------------------------------
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

    # ----------------------------------------------------------------
    # Metadata writers (called between png_set_IHDR and png_write_png).
    # ----------------------------------------------------------------
    # png_text is a struct; we pass an array pointer + count.
    attach_function :png_set_text,
                    %i[pointer pointer pointer int], :void
    # file_gamma is a double.
    attach_function :png_set_gAMA,
                    %i[pointer pointer double], :void
    attach_function :png_set_sRGB,
                    %i[pointer pointer int], :void
    # 8 chromaticity doubles (white_x, white_y, r_x, r_y, g_x, g_y, b_x, b_y).
    attach_function :png_set_cHRM,
                    %i[pointer pointer double double double double
                       double double double double], :void
    # png_set_iCCP(png_ptr, info_ptr, name, compression_type, profile, length)
    attach_function :png_set_iCCP,
                    %i[pointer pointer string int pointer uint], :void
    # png_set_pHYs(png_ptr, info_ptr, res_x, res_y, unit_type)
    attach_function :png_set_pHYs,
                    %i[pointer pointer uint32 uint32 int], :void

    # ----------------------------------------------------------------
    # libpng standard read API.
    # ----------------------------------------------------------------
    attach_function :png_create_read_struct,
                    %i[string pointer pointer pointer], :pointer
    attach_function :png_destroy_read_struct, %i[pointer pointer pointer], :void
    attach_function :png_set_read_fn,
                    %i[pointer pointer pointer pointer], :void
    attach_function :png_read_info, %i[pointer pointer], :void
    attach_function :png_read_update_info, %i[pointer pointer], :void
    attach_function :png_read_image, %i[pointer pointer], :void
    attach_function :png_read_end, %i[pointer pointer], :void
    # Returns the byte count per row AFTER any transforms are applied.
    attach_function :png_get_rowbytes, %i[pointer pointer], :size_t
    # Returns the post-transform color type / bit depth / channels.
    attach_function :png_get_color_type, %i[pointer pointer], :uint8
    attach_function :png_get_bit_depth, %i[pointer pointer], :uint8
    attach_function :png_get_channels, %i[pointer pointer], :uint8
    # Returns post-transform width / height (transforms rarely change these).
    attach_function :png_get_image_width, %i[pointer pointer], :uint32
    attach_function :png_get_image_height, %i[pointer pointer], :uint32
    attach_function :png_get_interlace_type, %i[pointer pointer], :uint8
    # png_get_IHDR signature differs from png_set_IHDR: widths are passed
    # by reference (pointer to uint32) so libpng can write them back.
    attach_function :png_get_IHDR,
                    %i[pointer pointer pointer pointer pointer pointer
                       pointer pointer pointer], :uint32

    # ----------------------------------------------------------------
    # Read-side transforms (call between png_read_info and png_read_image).
    # Each takes only (png_ptr); they toggle internal state.
    # ----------------------------------------------------------------
    attach_function :png_set_expand, [:pointer], :void
    attach_function :png_set_palette_to_rgb, [:pointer], :void
    attach_function :png_set_tRNS_to_alpha, [:pointer], :void
    attach_function :png_set_strip_alpha, [:pointer], :void
    attach_function :png_set_strip_16, [:pointer], :void
    attach_function :png_set_expand_gray_1_2_4_to_8, [:pointer], :void
    attach_function :png_set_gray_to_rgb, [:pointer], :void
    attach_function :png_set_rgb_to_gray, %i[pointer int double double], :void
    attach_function :png_set_filler, %i[pointer uint int], :void
    attach_function :png_set_add_alpha, %i[pointer uint int], :void
    attach_function :png_set_packing, [:pointer], :void
    attach_function :png_set_swap, [:pointer], :void
    attach_function :png_set_interlace_handling, [:pointer], :int
    attach_function :png_set_gamma, %i[pointer double double], :void

    # PNG_INFO_* bit flags returned by png_get_valid.
    attach_function :png_get_valid, %i[pointer pointer uint], :uint
  end
end
