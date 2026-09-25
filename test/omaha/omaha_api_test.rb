require 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'smart_proxy_omaha/configuration_loader'
require 'smart_proxy_omaha/omaha_plugin'
require 'smart_proxy_omaha/distribution'

ENV['RACK_ENV'] = 'test'

class TestForemanClient
  @@requests = {}

  def self.requests
    @@requests
  end

  def self.clear_requests
    @@requests = {}
  end

  def post_facts(factsdata)
    @@requests[:facts] ||= []
    @@requests[:facts] << JSON.parse(factsdata)
  end

  def post_report(report)
    @@requests[:reports] ||= []
    @@requests[:reports] << JSON.parse(report)
  end
end

class TestReleaseRepository
  def releases(track, architecture)
    ['1068.9.0', '1122.2.0'].map do |release|
      Proxy::Omaha::Release.new(
        :distribution => ::Proxy::Omaha::Distribution::Coreos.new,
        :track => 'alpha',
        :architecture => 'amd64-usr',
        :version => release
      )
    end
  end

  def tracks
    ['alpha', 'beta', 'stable']
  end

  def architectures(track)
    ['amd64-usr']
  end

  def latest_os(track, architecture)
    releases(track, architecture).max
  end
end

class TestMetadataProvider
  def get(track, release, architecture)
    Proxy::Omaha::Metadata.new(
      :track => track,
      :architecture => architecture,
      :release => release,
      :sha1_b64 => '+ZFmPWzv1OdfmKHaGSojbK5Xj3k=',
      :sha256_b64 => 'cSBzKN0c6vKinrH0SdqUZSHlQtCa90vmeKC7p/xk19M=',
      :size => '212555113'
    )
  end

  def store(metadata); end
end

class TestSyncStatus
  def last_sync_time
    '2026-09-25T03:45:00Z'
  end
end

module Proxy::Omaha
  module DependencyInjection
    include Proxy::DependencyInjection::Accessors
    def container_instance
      Proxy::DependencyInjection::Container.new do |c|
        c.singleton_dependency :foreman_client_impl, TestForemanClient
        c.singleton_dependency :release_repository_impl, TestReleaseRepository
        c.singleton_dependency :metadata_provider_impl, TestMetadataProvider
        c.singleton_dependency :sync_status_impl, TestSyncStatus
        c.singleton_dependency :distribution_impl, (lambda do
          ::Proxy::Omaha::Distribution::Coreos.new
        end)
      end
    end
  end
end

require 'smart_proxy_omaha/omaha_api'

class OmahaApiTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::Omaha::Api.new
  end

  def setup
    TestForemanClient.clear_requests
    @contentpath = Dir.mktmpdir
    Proxy::Omaha::Plugin.load_test_settings(contentpath: @contentpath)
  end

  def teardown
    FileUtils.rm_rf(@contentpath)
  end

  def test_processes_update_complete_noupdate
    Proxy::Omaha::OmahaProtocol::Handler.any_instance.stubs(:report_timestamp).returns('fake_timestamp')
    post "/v1/update", xml_fixture('request_update_complete_noupdate')
    assert last_response.ok?, "Last response was not ok: #{last_response.status} #{last_response.body}"
    assert_xml_equal xml_fixture('response_update_complete_noupdate'), last_response.body
    assert_equal [
      {
        'omaha_report' => {
          'host' => 'localhost',
          'status' => 'complete',
          'omaha_version' => '1122.2.0',
          'machineid' => '8e9450f47a4c47adbfe48b946e201c84',
          'omaha_group' => 'stable',
          'oem' => 'vmware',
          'reported_at' => 'fake_timestamp',
        },
      },
    ], TestForemanClient.requests[:reports]
  end

  def test_processes_update_complete_update
    post "/v1/update", xml_fixture('request_update_complete_update')
    assert last_response.ok?, "Last response was not ok: #{last_response.status} #{last_response.body}"
    assert_xml_equal xml_fixture('response_update_complete_update'), last_response.body
  end

  def test_processes_update_complete_error
    post "/v1/update", xml_fixture('request_update_complete_error')
    assert last_response.ok?, "Last response was not ok: #{last_response.status} #{last_response.body}"
    assert_xml_equal xml_fixture('response_update_complete_error'), last_response.body
  end

  def test_processes_ping
    post "/v1/update", xml_fixture('request_ping')
    assert last_response.ok?, "Last response was not ok: #{last_response.status} #{last_response.body}"
    assert_xml_equal xml_fixture('response_ping'), last_response.body
  end

  def test_processes_internalerror
    TestForemanClient.any_instance.stubs(:post_facts).raises(StandardError.new('Test Error'))
    post "/v1/update", xml_fixture('request_update_complete_update')
    refute last_response.ok?
    assert_xml_equal xml_fixture('response_errorinternal'), last_response.body
  end

  def test_get_tracks
    get "/tracks"
    assert last_response.ok?, "Last response was not ok: #{last_response.status} #{last_response.body}"
    parsed = JSON.parse(last_response.body)
    assert_kind_of Array, parsed
    assert_equal ['alpha', 'beta', 'stable'], parsed.map { |track| track['name'] }
  end

  def test_get_releases
    get "/tracks/alpha/amd64-usr"
    assert last_response.ok?, "Last response was not ok: #{last_response.status} #{last_response.body}"
    parsed = JSON.parse(last_response.body)
    assert_kind_of Array, parsed
    assert_equal ['1068.9.0', '1122.2.0'], parsed.map { |track| track['name'] }
  end

  def test_get_sync_status
    get '/sync', {}, { 'HTTP_HOST' => 'localhost' }
    assert last_response.ok?, "Last response was not ok: #{last_response.status} #{last_response.body}"
    assert_equal({ 'last_sync_time' => '2026-09-25T03:45:00Z' }, JSON.parse(last_response.body))
  end

  def test_ca
    Proxy::SETTINGS.stubs(:ssl_ca_file).returns(File.expand_path('../../fixtures/ca.crt', __FILE__))
    get '/ca'
    assert last_response.ok?, "Last response was not ok: #{last_response.status} #{last_response.body}"
    body = last_response.body
    assert_includes body, 'CERTIFICATE'
  end

  def test_ca_not_found
    Proxy::SETTINGS.stubs(:ssl_ca_file).returns(File.expand_path('../../fixtures/noca.crt', __FILE__))
    get '/ca'
    assert_equal 404, last_response.status
  end
end
