# frozen_string_literal: true

# extconf.rb is invoked by RubyGems when installing the source ('ruby'
# platform) gem. It needs to find lib/libpng.rb on the load path so it
# can trigger Libpng::Recipe autoload. We don't `require_relative`
# because that pins to a specific path; instead we extend $LOAD_PATH
# and let the normal autoload machinery do the work.
$LOAD_PATH << File.expand_path(File.join(File.dirname(__FILE__), '../lib'))

require 'mkmf'
require 'libpng' # triggers autoload setup; Libpng::Recipe loads lazily

recipe = Libpng::Recipe.for_target(ENV.fetch('target_platform', nil)).new
recipe.cook_if_not

# RubyGems requires every extconf.rb to leave a Makefile behind, even if
# no native extension is compiled (libpng is built by Recipe#cook above
# and loaded via FFI at runtime). dummy_makefile satisfies that contract.
create_makefile('libpng/dummy')
