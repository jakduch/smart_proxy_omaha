module ::Proxy::Omaha
  class ConfigurationLoader
    def load_classes
      require 'smart_proxy_omaha/dependency_injection'
      require 'smart_proxy_omaha/foreman_client'
      require 'smart_proxy_omaha/queued_foreman_client'
      require 'smart_proxy_omaha/omaha_api'
      require 'smart_proxy_omaha/distribution'
    end

    def load_dependency_injection_wirings(container_instance, settings)
      container_instance.singleton_dependency :foreman_client_impl, (lambda do
        Proxy::Omaha::QueuedForemanClient.new(
          Proxy::Omaha::ForemanClient.new,
          :queue_path => settings[:queuepath],
          :retry_interval => Integer(settings[:queue_retry_interval])
        )
      end)
      container_instance.singleton_dependency :distribution_impl, (lambda do
        Proxy::Omaha::Distribution.new(settings[:distribution])
      end)
      container_instance.singleton_dependency :release_repository_impl, (lambda do
        Proxy::Omaha::ReleaseRepository.new(
          :contentpath => settings[:contentpath],
          :distribution => container_instance.get_dependency(:distribution_impl)
        )
      end)
      container_instance.singleton_dependency :metadata_provider_impl, (lambda do
        Proxy::Omaha::MetadataProvider.new(:contentpath => settings[:contentpath])
      end)
    end
  end
end
