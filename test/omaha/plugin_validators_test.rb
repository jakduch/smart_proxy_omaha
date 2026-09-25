require 'test_helper'
require 'tmpdir'
require 'smart_proxy_omaha/plugin_validators'

class ContentPathValidatorTest < Test::Unit::TestCase
  def setup
    @contentpath = Dir.mktmpdir
    @validator = Proxy::Omaha::PluginValidators::ContentPathValidator.new(
      nil,
      :contentpath,
      true,
      nil
    )
  end

  def teardown
    FileUtils.chmod_R(0o700, @contentpath)
    FileUtils.rm_rf(@contentpath)
  end

  def test_readable_content
    FileUtils.mkdir_p(File.join(@contentpath, 'stable', 'amd64-usr'))
    File.write(File.join(@contentpath, 'stable', 'amd64-usr', 'metadata.json'), '{}')

    assert_true @validator.validate!(:contentpath => @contentpath)
  end

  def test_unreadable_content
    metadata = File.join(@contentpath, 'metadata.json')
    File.write(metadata, '{}')
    FileUtils.chmod(0o000, metadata)

    error = assert_raise(Proxy::Error::ConfigurationError) do
      @validator.validate!(:contentpath => @contentpath)
    end

    assert_match metadata, error.message
  end
end
