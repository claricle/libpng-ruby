$: << File.expand_path(File.join(File.dirname(__FILE__), '../lib'))

require 'libpng/recipe'

recipe = Libpng::Recipe.new
recipe.cook_if_not
