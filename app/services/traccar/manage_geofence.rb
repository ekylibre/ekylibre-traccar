module Traccar
  class ManageGeofence

    def initialize
      @cultivable_zones = CultivableZone.all
      @vendor = EkylibreTraccar::VENDOR
    end

    def update_geofences
      traccar_geofences = fetch_geofences
      # find and create or update geofences in Traccar from cultivable zone in Ekylibre
      # if existing geofences in Traccar not sync with Ekylibre, do nothing
      @cultivable_zones.each do |cz|
        # Check if the cultivable zone is already sync with Ekylibre in Traccar
        existing_geofence = traccar_geofences.find { |geofence| geofence[:attributes].any? && geofence[:attributes].key?(:uuid) && geofence[:attributes][:uuid] == cz.uuid } if traccar_geofences.any?
        if existing_geofence.present?
          # update from Ekylibre
          traccar_call = update_geofence(existing_geofence[:id], cz)
          cz.update(provider: { vendor: @vendor, name: 'geofence', data: { id: traccar_call[:id].to_s, updated_at: Time.now } })
          puts "Geofence #{cz.name} is updated in Traccar."
        else
          # Create a new geofence in Traccar
          traccar_call = create_geofence(cz)
          cz.update(provider: { vendor: @vendor, name: 'geofence', data: { id: traccar_call[:id].to_s, updated_at: Time.now } })
          puts "Geofence #{cz.name} created in Traccar."
        end
      end
    end
    

    private

        def fetch_geofences
          ::Traccar::TraccarIntegration.fetch_geofences.execute do |c|
            c.success do |geofences|
              geofences
            end
          end
        end

        def create_geofence(cz)
          # name, description, shape
          ::Traccar::TraccarIntegration.create_geofence(cz.compute_human_name, cz.compute_human_description, cz.shape_to_wkt_polygon(true), { uuid: cz.uuid }).execute do |c|
            c.success do |geofence|
              geofence
            end
          end
        end

        def update_geofence(id, cz)
          ::Traccar::TraccarIntegration.update_geofence(id, cz.compute_human_name, cz.compute_human_description, cz.shape_to_wkt_polygon(true), { uuid: cz.uuid }).execute do |c|
            c.success do |geofence|
              geofence
            end
          end
        end

  end
end