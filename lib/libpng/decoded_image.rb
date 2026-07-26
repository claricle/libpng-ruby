# frozen_string_literal: true

module Libpng
  # Result of {Libpng.decode}. A frozen-keyword Struct so it crosses
  # Ractor boundaries cleanly via moving semantics.
  #
  # +width+        image width in pixels (Integer)
  # +height+       image height in pixels (Integer)
  # +format+        pixel format String ("RGBA", "RGB", "GRAY", "GA")
  # +pixels+        binary String of raw pixel bytes, row-major top-down
  # +bit_depth+     bits per channel (8 or 16). nil if not extracted.
  # +color_type+    PNG_COLOR_TYPE_* integer from IHDR. nil if not extracted.
  # +interlace+     PNG_INTERLACE_* integer from IHDR. nil if not extracted.
  # +text+          Hash<String,String> of tEXt/zTXt/iTXt keyword -> UTF-8
  #                 value. Empty Hash when no text chunks present.
  # +color+         Hash<Symbol,*> of gAMA/cHRM/sRGB/iCCP fields. Empty
  #                 Hash when no color metadata present.
  DecodedImage = Struct.new(:width, :height, :format, :pixels,
                            :bit_depth, :color_type, :interlace,
                            :text, :color,
                            keyword_init: true)
end
