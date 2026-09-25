require 'smart_proxy_omaha/release'
require 'smart_proxy_omaha/track'
require 'smart_proxy_omaha/release_provider'
require 'smart_proxy_omaha/distribution'
require 'smart_proxy_omaha/sync_status'

module Proxy::Omaha
  class Syncer
    include ::Proxy::Log

    def run
      if sync_count == 0
        logger.info "Syncing is disabled."
        return
      end

      sync_results = Proxy::Omaha::Track.all.flat_map do |track|
        logger.debug "Syncing track: #{track}..."
        releases = release_provider(track).releases
        results = releases.last(sync_count).map do |release|
          sync_release(track, release)
        end
        update_current_release(track, releases.last) if releases.any?
        results
      end
      sync_status.record_success if sync_results.any? && sync_results.all?
    end

    def sync_release(track, release)
      if release.exists?
        if !release.valid?
          logger.info "#{track} release #{release} is invalid. Purging."
          release.purge
        elsif release.complete?
          logger.info "#{track} release #{release} exists, is complete and valid. Skipping sync."
          return true
        end
      end
      release.create
    end

    def update_current_release(track, release)
      logger.debug "#{track}: Updating current release to #{release}"
      release.mark_as_current!
    end

    private

    def sync_count
      Proxy::Omaha::Plugin.settings.sync_releases.to_i
    end

    def distribution
      Proxy::Omaha::Plugin.settings.distribution
    end

    def release_provider(track)
      @release_provider ||= {}
      @release_provider[track] ||= ReleaseProvider.new(
        :track => track,
        :distribution => ::Proxy::Omaha::Distribution.new(distribution)
      )
    end

    def sync_status
      @sync_status ||= SyncStatus.new(:contentpath => Proxy::Omaha::Plugin.settings.contentpath)
    end
  end
end
