# frozen_string_literal: true

module Libpng
  # Gem version follows the pattern:
  #
  #   {LIBPNG_VERSION}.{LIBPNG_RUBY_ITERATION}
  #
  # where LIBPNG_VERSION is the upstream libpng release this gem is
  # built against, and LIBPNG_RUBY_ITERATION is a counter for Ruby-side
  # changes (recipe bug fixes, CI changes, docs) that bump without a
  # new libpng release. The iteration resets to 0 each time
  # LIBPNG_VERSION bumps.
  LIBPNG_VERSION = '1.6.58'
  LIBPNG_RUBY_ITERATION = 0
  VERSION = "#{LIBPNG_VERSION}.#{LIBPNG_RUBY_ITERATION}"
end
