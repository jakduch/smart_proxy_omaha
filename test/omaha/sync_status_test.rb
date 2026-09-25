require 'test_helper'
require 'tmpdir'
require 'smart_proxy_omaha/sync_status'

class SyncStatusTest < Test::Unit::TestCase
  def setup
    @contentpath = Dir.mktmpdir
    @status = Proxy::Omaha::SyncStatus.new(:contentpath => @contentpath)
  end

  def teardown
    FileUtils.rm_rf(@contentpath)
  end

  def test_records_last_successful_sync_time
    @status.record_success(Time.utc(2026, 9, 25, 3, 45, 0))

    assert_equal '2026-09-25T03:45:00Z', @status.last_sync_time
  end

  def test_returns_nil_before_first_successful_sync
    assert_nil @status.last_sync_time
  end

  def test_returns_nil_for_an_invalid_status_file
    File.write(File.join(@contentpath, Proxy::Omaha::SyncStatus::FILENAME), 'not json')

    assert_nil @status.last_sync_time
  end
end
