require 'rest-client'

module Traccar
  mattr_reader :default_options do
    {
      globals: {
        strip_namespaces: true,
        convert_response_tags_to: ->(tag) { tag.snakecase.to_sym },
        raise_errors: true
      },
      locals: {
        advanced_typecasting: true
      }
    }
  end

  class ServiceError < StandardError; end

  class TraccarIntegration < ActionIntegration::Base

    authenticate_with :check do
      parameter :server_url
      parameter :email
      parameter :password
    end

    calls :fetch_users

    # https://api-doc.baqio.com/docs/api-doc/Baqio-Public-API.v1.json/paths/~1payment_sources/get
    def fetch_users
      integration = fetch
      # Call API
      get_json(base_url(integration, "users"), authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    def check(integration = nil)
      integration = fetch integration
      get_json(base_url(integration, "server"), authentication_header(integration)) do |r|
        r.success do
          puts 'check success'.inspect.green
        end
      end
    end

    private

    def base_url(integration, endpoint)
      integration.parameters['server_url'] + "/api/#{endpoint}"
    end

    def authentication_header(integration)
      string_to_encode = "#{integration.parameters['email']}:#{integration.parameters['password']}"
      auth_encode = Base64.encode64(string_to_encode).delete("\n")
      { authorization: "Basic #{auth_encode}", 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    end

  end
end
