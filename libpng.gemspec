# frozen_string_literal: true

require_relative 'lib/libpng/version'

Gem::Specification.new do |spec|
  spec.name          = 'libpng'
  spec.version       = Libpng::VERSION
  spec.authors       = ['Ribose Inc.']
  spec.email         = ['open.source@ribose.com']

  spec.summary       = 'libpng for Ruby (pre-compiled, FFI-based).'
  spec.description   = 'Ruby binding for libpng via FFI. The native ' \
                       'libpng16 shared library is pre-compiled for ' \
                       'each target platform and shipped inside the ' \
                       'gem, so no C compiler is required at install time.'
  spec.homepage      = 'https://github.com/claricle/libpng-ruby'
  spec.license       = 'BSD-2-Clause'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/README.adoc#versioning"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{\A(?:test|spec|features|tmp|ports)/})
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'ffi', '~> 1.0'
  spec.add_dependency 'mini_portile2', '~> 2.6'

  spec.extensions = ['ext/extconf.rb']
end
