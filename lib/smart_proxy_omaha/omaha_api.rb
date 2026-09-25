require 'sinatra'
require 'smart_proxy_omaha/omaha_protocol'
require 'smart_proxy_omaha/release_repository'

module Proxy::Omaha
  class Api < ::Sinatra::Base
    extend Proxy::Omaha::DependencyInjection

    helpers ::Proxy::Helpers

    inject_attr :foreman_client_impl, :foreman_client
    inject_attr :release_repository_impl, :release_repository
    inject_attr :metadata_provider_impl, :metadata_provider
    inject_attr :distribution_impl, :distribution
    inject_attr :sync_status_impl, :sync_status

    post '/v1/update' do
      request.body.rewind
      request_body = request.body.read
      omaha_request = Proxy::Omaha::OmahaProtocol::Request.new(
        request_body,
        :ip => request.ip,
        :base_url => request.base_url,
        :distribution => distribution.identifier
      )
      omaha_handler = Proxy::Omaha::OmahaProtocol::Handler.new(
        :request => omaha_request,
        :foreman_client => foreman_client,
        :repository => release_repository,
        :metadata_provider => metadata_provider
      )
      response = omaha_handler.handle
      status response.http_status
      response.to_xml
    end

    get '/tracks' do
      release_repository.tracks.map do |track|
        {
          :name => track,
          :architectures => release_repository.architectures(track),
        }
      end.to_json
    end

    get '/tracks/:track/:architecture' do |track, architecture|
      not_found unless release_repository.tracks.include?(track)
      not_found unless release_repository.architectures(track).include?(architecture)
      release_repository.releases(track, architecture).map do |release|
        release.to_h.merge(
          :file_urls => release.file_urls(request.base_url)
        )
      end.to_json
    end

    get '/sync' do
      {
        :last_sync_time => sync_status.last_sync_time,
      }.to_json
    end

    get '/ca' do
      not_found if Proxy::SETTINGS.ssl_ca_file.nil? || Proxy::SETTINGS.ssl_ca_file.empty? || !File.exist?(Proxy::SETTINGS.ssl_ca_file)
      content_type 'text/plain'
      File.read(Proxy::SETTINGS.ssl_ca_file)
    end
  end
end
