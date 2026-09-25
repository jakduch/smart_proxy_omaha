require 'json'
require 'tempfile'
require 'time'

module Proxy::Omaha
  class SyncStatus
    FILENAME = '.last_sync.json'.freeze

    def initialize(options)
      @status_file = File.join(options.fetch(:contentpath), FILENAME)
    end

    def record_success(time = Time.now.utc)
      temporary_file = Tempfile.new(['.last-sync-', '.json'], File.dirname(status_file))
      temporary_file.write({ :last_sync_time => time.utc.iso8601 }.to_json)
      temporary_file.flush
      temporary_file.fsync
      temporary_file.close
      File.rename(temporary_file.path, status_file)
    ensure
      temporary_file&.close!
    end

    def last_sync_time
      return unless File.file?(status_file)
      JSON.parse(File.read(status_file)).fetch('last_sync_time')
    rescue Errno::ENOENT, JSON::ParserError, KeyError
      nil
    end

    private

    attr_reader :status_file
  end
end
