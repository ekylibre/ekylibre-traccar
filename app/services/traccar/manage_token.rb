module Traccar
  class ManageToken

    def initialize
      @vendor = EkylibreTraccar::VENDOR
      @integration = Integration.find_by(nature: @vendor)
    end

    def create_user_link
      expired_at = Time.parse(@integration.parameters['token_expired_at']) if @integration.parameters['token_expired_at'].present?
      if expired_at.nil? || expired_at < Time.now
        token_expired_at = Time.now + 7.days
        token = create_token(token_expired_at)
        @integration.parameters['token'] = token
        @integration.parameters['token_expired_at'] = token_expired_at.to_s
        @integration.parameters['web_url'] = "#{@integration.parameters['server_url']}/?token=#{@integration.parameters['token']}"
        @integration.save
      end
    end

    private

        def create_token(token_expired_at)
          ::Traccar::TraccarIntegration.create_token(token_expired_at).execute do |c|
            c.success do |token|
              token
            end
          end
        end

  end
end