# frozen_string_literal: true

require 'pathname'

module Libpng
  module OHOS
    # Wraps OHOS's binary-sign-tool to apply -selfSign 1 to a freshly
    # built shared library. Mandatory for runtime loading on production
    # OHOS devices; dockerharmony skips this check (dev container).
    #
    # Design: #sign_command is a pure-data accessor returning the argv
    # that #sign would run. Specs assert on the command shape without
    # actually invoking the tool -- no doubles needed.
    class CodeSigner
      def initialize(ndk)
        @ndk = ndk
      end

      # Returns the argv for the signing invocation. Pure data.
      def sign_command(so_path)
        [
          @ndk.sign_tool_path.to_s,
          'sign',
          '-selfSign', '1',
          '-inFile', so_path.to_s,
          '-outFile', so_path.to_s
        ]
      end

      # Runs binary-sign-tool on the .so, in-place. Returns true on
      # success, false otherwise. Caller (OHOS::Recipe#install) raises
      # on false.
      def sign(so_path)
        system(*sign_command(so_path))
      end
    end
  end
end
