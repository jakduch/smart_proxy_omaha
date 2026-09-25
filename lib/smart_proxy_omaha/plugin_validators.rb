require 'find'

module Proxy
  module Omaha
    module PluginValidators
      class ContentPathValidator < ::Proxy::PluginValidators::Base
        def validate!(settings)
          contentpath = settings[@setting_name]
          unreadable_path = Find.find(contentpath).find do |path|
            !File.readable?(path) || (File.directory?(path) && !File.executable?(path))
          end

          if unreadable_path
            raise ::Proxy::Error::ConfigurationError,
                  "Omaha content at '#{unreadable_path}' is unreadable by the smart proxy user"
          end

          true
        end
      end

      class DistributionValidator < ::Proxy::PluginValidators::Base
        def validate!(settings)
          raise ::Proxy::Error::ConfigurationError, "Setting '#{@setting_name}' must be a supported Omaha distribution ('coreos' or 'flatcar')" unless ['coreos', 'flatcar'].include?(settings[@setting_name])
        end
      end
    end
  end
end
