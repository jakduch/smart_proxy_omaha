require 'test_helper'
require 'smart_proxy_omaha/configuration_loader'
require 'smart_proxy_omaha/omaha_plugin'
require 'smart_proxy_omaha/syncer'

class SyncerTest < Test::Unit::TestCase

  class FakeRelease
    def exists?
      false
    end

    def valid?
      true
    end

    def complete?
      true
    end

    def create
      true
    end
    def mark_as_current!; end
  end

  class FakeReleaseProvider
    def releases
      3.times.map { FakeRelease.new }
    end
  end

  def setup
    Proxy::Omaha::Plugin.load_test_settings({ :sync_releases => 1 })
    @provider = FakeReleaseProvider.new
    @syncer = Proxy::Omaha::Syncer.new
    @syncer.stubs(:release_provider).returns(@provider)
    @sync_status = mock
    @sync_status.stubs(:record_success)
    @syncer.stubs(:sync_status).returns(@sync_status)
  end

  def test_sync
    FakeRelease.any_instance.expects(:create).times(3).returns(true)
    @sync_status.expects(:record_success).once
    @syncer.run
  end

  def test_sync_existing
    FakeRelease.any_instance.stubs(:exists?).returns(true)
    FakeRelease.any_instance.expects(:create).never
    @syncer.run
  end

  def test_failed_sync_is_not_recorded
    FakeRelease.any_instance.stubs(:create).returns(false)
    @sync_status.expects(:record_success).never

    @syncer.run
  end

  def test_empty_upstream_is_not_recorded_as_a_successful_sync
    @provider.stubs(:releases).returns([])
    @sync_status.expects(:record_success).never

    @syncer.run
  end
end
