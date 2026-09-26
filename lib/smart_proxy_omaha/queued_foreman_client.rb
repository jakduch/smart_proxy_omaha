require 'fileutils'
require 'json'
require 'securerandom'
require 'tempfile'

module Proxy::Omaha
  class QueuedForemanClient
    include ::Proxy::Log

    class InvalidQueueEntry < StandardError; end

    def initialize(foreman_client, options = {})
      @foreman_client = foreman_client
      @queue_path = options.fetch(:queue_path)
      @retry_interval = options.fetch(:retry_interval, 30)
      raise ArgumentError, 'retry_interval must be greater than zero' unless @retry_interval.positive?

      @worker_enabled = options.fetch(:start_worker, true)
      @worker_mutex = Mutex.new
      @worker_signal = ConditionVariable.new
      @wake_requested = false

      FileUtils.mkdir_p(@queue_path, :mode => 0o700)
      start_worker if @worker_enabled
    end

    def post_facts(factsdata)
      enqueue(:facts, factsdata)
    end

    def post_report(report)
      enqueue(:report, report)
    end

    def drain
      delivered = 0

      queued_files.each do |path|
        job = JSON.parse(File.read(path))
        deliver(job)
        File.delete(path)
        delivered += 1
      rescue JSON::ParserError, InvalidQueueEntry => e
        quarantine(path, e)
      rescue StandardError => e
        logger.warn "Omaha delivery queue: #{e.message}; retrying in #{@retry_interval} seconds"
        break
      end

      delivered
    end

    private

    def enqueue(type, payload)
      target = File.join(@queue_path, queue_filename)
      tempfile = Tempfile.new(['.omaha-delivery-', '.json'], @queue_path)
      tempfile.chmod(0o600)
      tempfile.write(JSON.generate('type' => type, 'payload' => payload))
      tempfile.flush
      tempfile.fsync
      tempfile.close
      File.rename(tempfile.path, target)
      wake_worker
      true
    ensure
      tempfile&.close!
    end

    def queue_filename
      timestamp = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
      format('%020d-%s.json', timestamp, SecureRandom.hex(8))
    end

    def queued_files
      Dir.glob(File.join(@queue_path, '*.json')).sort
    end

    def deliver(job)
      unless job.is_a?(Hash) && job.key?('type') && job.key?('payload')
        raise InvalidQueueEntry, 'entry must contain a type and payload'
      end

      case job.fetch('type')
      when 'facts'
        @foreman_client.post_facts(job.fetch('payload'))
      when 'report'
        @foreman_client.post_report(job.fetch('payload'))
      else
        raise InvalidQueueEntry, "unknown delivery type #{job['type'].inspect}"
      end
    end

    def quarantine(path, error)
      invalid_path = "#{path}.invalid"
      File.rename(path, invalid_path)
      logger.error "Omaha delivery queue: moved invalid entry to #{invalid_path}: #{error.message}"
    end

    def start_worker
      @worker = Thread.new do
        loop do
          drain
          wait_for_work
        end
      end
      @worker.name = 'omaha-delivery' if @worker.respond_to?(:name=)
      @worker.report_on_exception = false if @worker.respond_to?(:report_on_exception=)
    end

    def wake_worker
      return unless @worker_enabled

      @worker_mutex.synchronize do
        @wake_requested = true
        @worker_signal.signal
      end
    end

    def wait_for_work
      @worker_mutex.synchronize do
        @worker_signal.wait(@worker_mutex, @retry_interval) unless @wake_requested
        @wake_requested = false
      end
    end
  end
end
