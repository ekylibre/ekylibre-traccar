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

    calls :fetch_positions, :fetch_devices, :fetch_geofences, :fetch_drivers, :fetch_trips,
          :create_driver, :create_geofence, :create_device, :update_device, :update_geofence,
          :create_token

    # POSITIONS / CRUMBS
    # https://www.traccar.org/api-reference/#tag/Positions/paths/~1positions/get
    #
    # response example
    # {
    #   "id": 9919,
    #   "attributes": {
    #     "tool": "épandeur à fumier\r\n6 m",
    #     "Work": "False",
    #     "Field": "Bellerie\r\n0,00 ha",
    #     "AppliedArea": "0,00",
    #     "distance": 5912.334438816946,
    #     "totalDistance": 5915.274736441744,
    #     "motion": false
    #   },
    #   "deviceId": 7,
    #   "protocol": "osmand",
    #   "serverTime": "2025-05-05T12:39:15.000+00:00",
    #   "deviceTime": "2025-05-05T12:39:13.000+00:00",
    #   "fixTime": "2025-05-05T12:39:13.000+00:00",
    #   "outdated": false,
    #   "valid": true,
    #   "latitude": 47.4492008333333,
    #   "longitude": -1.57158216666667,
    #   "altitude": 0,
    #   "speed": 0,
    #   "course": 0,
    #   "address": null,
    #   "accuracy": 0,
    #   "network": null,
    #   "geofenceIds": null
    # }
    
    def fetch_positions(device_id, from, to)
      integration = fetch

      endpoint = "positions"
      endpoint += "?deviceId=#{device_id}" if device_id
      endpoint += "&from=#{from}" if from
      endpoint += "&to=#{to}" if to
      # Call API
      get_json(base_url(integration, endpoint), authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    # TRIPS / RIDE_SETS
    #   {
    #   "deviceId": 10,
    #   "deviceName": "Fendt 920",
    #   "distance": 294.85399976582266,
    #   "averageSpeed": 1.0271487435569833,
    #   "maxSpeed": 0,
    #   "spentFuel": 0,
    #   "startOdometer": 1520954.1528470211,
    #   "endOdometer": 1521249.006846787,
    #   "startTime": "2025-05-14T12:45:20.000+00:00",
    #   "endTime": "2025-05-14T12:54:38.000+00:00",
    #   "startPositionId": 61097,
    #   "endPositionId": 61235,
    #   "startLat": 45.827842,
    #   "startLon": -0.7835869,
    #   "endLat": 45.8279657,
    #   "endLon": -0.7842337,
    #   "startAddress": "8 Rue du Bouil Bleu, Saint-Porchaire, Nouvelle-Aquitaine, FR",
    #   "endAddress": null,
    #   "duration": 558000,
    #   "driverUniqueId": null,
    #   "driverName": null
    # }
    def fetch_trips(device_id, from, to)
      integration = fetch

      endpoint = "reports/trips"
      endpoint += "?deviceId=#{device_id}" if device_id
      endpoint += "&from=#{from}" if from
      endpoint += "&to=#{to}" if to
      # Call API
      get_json(base_url(integration, endpoint), authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    # DEVICES / EQUIPMENTS
    # https://www.traccar.org/api-reference/#tag/Devices/paths/~1devices/post
    # {
    # "id": 7,
    # "attributes": {},
    # "groupId": 0,
    # "calendarId": 0,
    # "name": "Arion610",
    # "uniqueId": "Arion610",
    # "status": "unknown",
    # "lastUpdate": "2025-05-05T13:15:18.000+00:00",
    # "positionId": 10330,
    # "phone": null,
    # "model": null,
    # "contact": null,
    # "category": null,
    # "disabled": false,
    # "expirationTime": null
    # }

    def fetch_devices
      integration = fetch

      endpoint = "devices"
      # Call API
      get_json(base_url(integration, endpoint), authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    def create_device(name, work_number, model, category, attributes = {})
      integration = fetch

      endpoint = "devices"
      payload = {
        id: nil,
        name: name,
        uniqueId: work_number,
        disabled: false,
        model: model,
        category: category,
        attributes: { uuid: attributes["uuid"] }
      }
      # Call API
      post_json(base_url(integration, endpoint), payload, authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).deep_symbolize_keys
        end
      end
    end

    def update_device(id, name, work_number, model, category, attributes = {})
      integration = fetch

      endpoint = "devices/#{id}"
      payload = {
        id: id,
        name: name,
        uniqueId: work_number,
        disabled: false,
        model: model,
        category: category,
        attributes: { uuid: attributes["uuid"] }
      }
      # Call API
      put_json(base_url(integration, endpoint), payload, authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).deep_symbolize_keys
        end
      end
    end

    # GEOFENCES / CULTIVABLES_ZONES
    # {
    # "id": 3,
    # "attributes": {},
    # "calendarId": 0,
    # "name": "Castagnet",
    # "description": null,
    # "area": "POLYGON ((43.38827150557057 -0.2050419195788038, 43.388377215895304 -0.20470553566235594, 43.388479622597174 -0.2044737035037656, 43.38853578103726 -0.2042191427025557, 43.388615063452704 -0.20392367034364156, 43.388790145085835 -0.20360546934207946, 43.388928888662264 -0.20326908542557476, 43.38898174327497 -0.20300088743792344, 43.387809020731055 -0.20168717187328866, 43.38770330941537 -0.20171899197305265, 43.38733662185916 -0.20208265026153072, 43.38702278840563 -0.20239630553456323, 43.386725471003246 -0.20272814372253833, 43.38649091957879 -0.20302816180992522, 43.386715560398414 -0.20330545125463573, 43.386811362853535 -0.2034736432121349, 43.38684439813932 -0.20359183215569487, 43.38715162549377 -0.20384184722917098, 43.38740269185314 -0.2040691336584075, 43.38754143860547 -0.2042191427025557, 43.38770661289675 -0.2044873406893828, 43.38784866242699 -0.2047146271193867, 43.388093118979214 -0.20491918490671424, 43.38827150557057 -0.2050419195788038))"
    # }

    def fetch_geofences
      integration = fetch

      endpoint = "geofences"
      # Call API
      get_json(base_url(integration, endpoint), authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    def create_geofence(name, description, shape, attributes = {})
      integration = fetch

      endpoint = "geofences"
      payload = {
        id: nil,
        attributes: { uuid: attributes["uuid"] },
        calendarId: nil,
        name: name,
        description: description,
        area: shape
      }
      # Call API
      post_json(base_url(integration, endpoint), payload, authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).deep_symbolize_keys
        end
      end
    end

    def update_geofence(id, name, description, shape, attributes = {})
      integration = fetch

      endpoint = "geofences/#{id}"
      payload = {
        id: id,
        attributes: { uuid: attributes["uuid"] },
        calendarId: nil,
        name: name,
        description: description,
        area: shape
      }
      # Call API
      put_json(base_url(integration, endpoint), payload, authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).deep_symbolize_keys
        end
      end
    end

    # DRIVERS / WORKERS
    # {
    # "id": 1,
    # "attributes": {},
    # "name": "Pierre",
    # "uniqueId": "PH"
    # }

    def fetch_drivers
      integration = fetch

      endpoint = "drivers"
      # Call API
      get_json(base_url(integration, endpoint), authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    def create_driver(name: nil, id: nil, attributes: {})
      integration = fetch

      endpoint = "drivers"
      payload = {
        id: nil,
        attributes: { uuid: attributes[:uuid] },
        name: name,
        uniqueId: id
      }
      # Call API
      post_json(base_url(integration, endpoint), payload, authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).deep_symbolize_keys
        end
      end
    end

    # CALENDARS / PERIODS - CAMPAIGN
    # data attribute is base64 encoded in iCalendar format
    # {
    # "id": 1,
    # "attributes": {},
    # "name": "Mais 2025",
    # "data": "QkVHSU46VkNBTEVOREFSClZFUlNJT046Mi4wClBST0RJRDotLy9UcmFjY2FyLy9OT05TR01MIFRyYWNjYXIvL0VOCkJFR0lOOlZFVkVOVApVSUQ6MDAwMDAwMDAtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAwCkRUU1RBUlQ7VFpJRD1FdXJvcGUvUGFyaXM6MjAyNTA1MDFUMTUwMTAwCkRURU5EO1RaSUQ9RXVyb3BlL1BhcmlzOjIwMjUxMDMxVDE2MDEwMApSUlVMRTpGUkVRPURBSUxZClNVTU1BUlk6RXZlbnQKRU5EOlZFVkVOVApFTkQ6VkNBTEVOREFS"
    # }

    def fetch_calendars
      integration = fetch

      endpoint = "calendars"
      # Call API
      get_json(base_url(integration, endpoint), authentication_header(integration)) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    # TOKEN for web url

    def create_token(expired_at = nil)
      integration = fetch
      if expired_at.present?
        expired_at = Time.parse(expired_at).utc.iso8601
      else
        expired_at = (Time.now + 7.days).utc.iso8601
      end
      endpoint = "session/token"
      payload = { expiration: expired_at }
      encoded_payload = URI.encode_www_form(payload)
      # Call API
      post_json(base_url(integration, endpoint), encoded_payload, authentication_header(integration, true)) do |r|
        r.success do
          r.body
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

    def authentication_header(integration, form_encoded = false)
      string_to_encode = "#{integration.parameters['email']}:#{integration.parameters['password']}"
      auth_encode = Base64.encode64(string_to_encode).delete("\n")
      if form_encoded
        { authorization: "Basic #{auth_encode}", 'Content-Type' => 'application/x-www-form-urlencoded', 'Accept' => 'application/json' }
      else
        { authorization: "Basic #{auth_encode}", 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
      end
    end

  end
end
