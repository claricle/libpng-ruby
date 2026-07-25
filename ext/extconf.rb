$: << File.expand_path(File.join(File.dirname(__FILE__), '../lib'))

require 'libpng/recipe'
require 'mkmf'

recipe = Libpng::Recipe.new
recipe.cook_if_not

# RubyGems requires every extconf.rb to leave a Makefile behind, even if
# no native extension is compiled (libpng is built by Recipe#cook above
# and loaded via FFI at runtime). dummy_makefile satisfies that contract.
create_makefile('libpng/dummy')
