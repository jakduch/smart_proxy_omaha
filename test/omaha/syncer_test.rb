require 'test_helper'
require 'smart_proxy_omaha/configuration_loader'
require 'smart_proxy_omaha/omaha_plugin'
require 'smart_proxy_omaha/syncer'

class SyncerTest < Test::Unit::TestCase

  class FakeRelease
    attr_reader :name

    def initialize(name = 'release')
      @name = name
    end

    def exists?
      false
    end

    def valid?
      true
    end

    def complete?
      true
    end

    def create; end
    def mark_as_current!; end
    def purge; end
  end

  class FakeReleaseProvider
    def architecture
      'amd64-usr'
    end

    def releases
      3.times.map { FakeRelease.new }
    end
  end

  def setup
    Proxy::Omaha::Plugin.load_test_settings({ :sync_releases => 1 })
    @provider = FakeReleaseProvider.new
    @syncer = Proxy::Omaha::Syncer.new
    @syncer.stubs(:release_provider).returns(@provider)
  end

  def test_sync
    FakeRelease.any_instance.expects(:create).times(3)
    @syncer.run
  end

  def test_sync_existing
    FakeRelease.any_instance.stubs(:exists?).returns(true)
    FakeRelease.any_instance.expects(:create).never
    @syncer.run
  end

  def test_cleanup_old_releases
    Proxy::Omaha::Plugin.load_test_settings({ :sync_releases => 1, :purge_old_releases => true })
    retained_release = FakeRelease.new('retained')
    old_release = FakeRelease.new('old')
    repository = mock
    repository.expects(:releases).with('stable', 'amd64-usr').returns([old_release, retained_release])
    @syncer.stubs(:release_repository).returns(repository)

    old_release.expects(:purge).once
    retained_release.expects(:purge).never

    @syncer.cleanup_releases('stable', [retained_release])
  end

  def test_cleanup_is_disabled_by_default
    release = FakeRelease.new('old')
    release.expects(:purge).never

    @syncer.cleanup_releases('stable', [])
  end

  def test_failed_sync_does_not_cleanup_old_releases
    Proxy::Omaha::Plugin.load_test_settings({ :sync_releases => 1, :purge_old_releases => true })
    FakeRelease.any_instance.stubs(:create).returns(false)
    @syncer.expects(:cleanup_releases).never

    @syncer.run
  end

  def test_empty_upstream_does_not_cleanup_old_releases
    Proxy::Omaha::Plugin.load_test_settings({ :sync_releases => 1, :purge_old_releases => true })
    @provider.stubs(:releases).returns([])
    @syncer.expects(:cleanup_releases).never

    @syncer.run
  end
end
