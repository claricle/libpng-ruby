# frozen_string_literal: true

module Libpng
  # Raised on any libpng-side failure: bad dimensions, unknown pixel
  # format, corrupt PNG input, libpng-internal error captured via the
  # error callback, etc.
  class Error < StandardError; end
end
