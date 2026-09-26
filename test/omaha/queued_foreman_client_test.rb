require 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'smart_proxy_omaha/queued_foreman_client'

class QueuedForemanClientTest < Test::Unit::TestCase
  class ForemanClient
    attr_accessor :fail_delivery
    attr_reader :facts, :reports

    def initialize
      @facts = []
      @reports = []
    end

    def post_facts(payload)
      raise 'Foreman is unavailable' if fail_delivery

      facts << payload
    end

    def post_report(payload)
      raise 'Foreman is unavailable' if fail_delivery

      reports << payload
    end
  end

  def setup
    @queue_path = Dir.mktmpdir
    @foreman_client = ForemanClient.new
    @client = Proxy::Omaha::QueuedForemanClient.new(
      @foreman_client,
      :queue_path => @queue_path,
      :retry_interval => 1,
      :start_worker => false
    )
  end

  def teardown
    FileUtils.rm_rf(@queue_path)
  end

  def test_queues_delivery_without_calling_foreman
    assert @client.post_facts('{"name":"host.example.test"}')

    assert_empty @foreman_client.facts
    assert_equal 1, queued_files.size
    assert_equal 0o600, File.stat(queued_files.first).mode & 0o777
  end

  def test_delivers_queued_facts_and_reports
    @client.post_facts('{"name":"host.example.test"}')
    @client.post_report('{"status":"complete"}')

    assert_equal 2, @client.drain
    assert_equal ['{"name":"host.example.test"}'], @foreman_client.facts
    assert_equal ['{"status":"complete"}'], @foreman_client.reports
    assert_empty queued_files
  end

  def test_delivers_entries_queued_by_a_previous_process
    @client.post_facts('{"name":"host.example.test"}')
    restarted_client = Proxy::Omaha::QueuedForemanClient.new(
      @foreman_client,
      :queue_path => @queue_path,
      :retry_interval => 1,
      :start_worker => false
    )

    assert_equal 1, restarted_client.drain
    assert_equal ['{"name":"host.example.test"}'], @foreman_client.facts
  end

  def test_keeps_delivery_for_retry_when_foreman_is_unavailable
    @foreman_client.fail_delivery = true
    @client.post_report('{"status":"complete"}')

    assert_equal 0, @client.drain
    assert_equal 1, queued_files.size

    @foreman_client.fail_delivery = false
    assert_equal 1, @client.drain
    assert_empty queued_files
  end

  def test_quarantines_invalid_queue_entries
    File.write(File.join(@queue_path, 'invalid.json'), 'not json')

    assert_equal 0, @client.drain
    assert_empty queued_files
    assert File.exist?(File.join(@queue_path, 'invalid.json.invalid'))
  end

  def test_quarantines_entries_with_an_invalid_schema
    File.write(File.join(@queue_path, 'invalid.json'), '{"type":"facts"}')

    assert_equal 0, @client.drain
    assert_empty queued_files
    assert File.exist?(File.join(@queue_path, 'invalid.json.invalid'))
  end

  def test_rejects_non_positive_retry_interval
    assert_raises(ArgumentError) do
      Proxy::Omaha::QueuedForemanClient.new(
        @foreman_client,
        :queue_path => @queue_path,
        :retry_interval => 0,
        :start_worker => false
      )
    end
  end

  private

  def queued_files
    Dir.glob(File.join(@queue_path, '*.json'))
  end
end
