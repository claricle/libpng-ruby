# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'libpng/ohos'

RSpec.describe Libpng::OHOS::CodeSigner do
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:ndk) { Libpng::OHOS::NDK.new(root: root) }
  let(:signer) { described_class.new(ndk) }
  let(:so_path) { Pathname.new('/tmp/libpng16.so') }

  before do
    sign_tool = root.join('ohos-sdk/linux/toolchains/lib/binary-sign-tool')
    sign_tool.dirname.mkpath
    FileUtils.touch(sign_tool)
  end

  after { FileUtils.rm_rf(root) }

  describe '#sign_command' do
    subject(:cmd) { signer.sign_command(so_path) }

    it 'is an Array of Strings' do
      expect(cmd).to be_an(Array)
      expect(cmd).to all(be_a(String))
    end

    it 'starts with the path to binary-sign-tool' do
      expect(cmd.first).to end_with('ohos-sdk/linux/toolchains/lib/binary-sign-tool')
    end

    it 'passes the sign subcommand' do
      expect(cmd).to include('sign')
    end

    it 'passes -selfSign with value 1' do
      self_sign_idx = cmd.index('-selfSign')
      expect(self_sign_idx).not_to be_nil
      expect(cmd[self_sign_idx + 1]).to eq('1')
    end

    it 'signs in-place (inFile and outFile are the same path)' do
      in_idx = cmd.index('-inFile')
      out_idx = cmd.index('-outFile')
      expect(in_idx).not_to be_nil
      expect(out_idx).not_to be_nil
      expect(cmd[in_idx + 1]).to eq(so_path.to_s)
      expect(cmd[out_idx + 1]).to eq(so_path.to_s)
    end

    it 'accepts a String path as well as a Pathname' do
      cmd_str = signer.sign_command('/tmp/foo.so')
      expect(cmd_str).to include('-inFile', '/tmp/foo.so')
    end
  end
end
