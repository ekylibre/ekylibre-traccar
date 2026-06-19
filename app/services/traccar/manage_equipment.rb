module Traccar
  class ManageEquipment

    def initialize
      @equipments = Equipment.tractors
      @vendor = EkylibreTraccar::VENDOR
    end

    def update_devices
      traccar_devices = fetch_devices
      # find or create devices in Traccar from tractor only in Ekylibre
      @equipments.each do |equipment|
        # Check if the equipment is already sync with Ekylibre in Traccar
        traccar_device = traccar_devices.find { |device| device[:attributes].any? && device[:attributes].key?(:uuid) && device[:attributes][:uuid] == equipment.uuid } if traccar_devices.any?
        # Check if the equipment is already in Traccar but not sync with Ekylibre
        traccar_not_sync_device = traccar_devices.find { |device| !device[:attributes].key?(:uuid) && device[:uniqueId] == equipment.work_number } if traccar_devices.any?
        if traccar_device.present?
          # check if id is already set in Ekylibre or not because server can change
          if equipment.provider_data[:id].to_s != traccar_device[:id].to_s
            sync_provider(equipment, traccar_device[:id])
            puts "Device #{equipment.name} already exists in Traccar and Ekylibre but server has change."
          else
            puts "Device #{equipment.name} already exists in Traccar and Ekylibre."
          end
        elsif traccar_not_sync_device.present?
          # Update device in Traccar with uuid
          traccar_call = update_device(traccar_not_sync_device[:id], equipment)
          sync_provider(equipment, traccar_call[:id])
          puts "Device #{equipment.name} already exists in Traccar and Ekylibre but not sync with Ekylibre."
        else
          # Create a new device in Traccar
          traccar_call = create_device(equipment)
          sync_provider(equipment, traccar_call[:id])
          puts "Device #{equipment.name} created in Traccar."
        end
      end
    end
    

    private

        def fetch_devices
          result = ::Traccar::TraccarIntegration.fetch_devices.execute do |c|
            c.success do |devices|
              devices
            end
          end
          result.is_a?(Array) ? result : []
        rescue StandardError => e
          Rails.logger.error "[Traccar] fetch_devices failed: #{e.class}: #{e.message}"
          []
        end

        def create_device(equipment)
          ::Traccar::TraccarIntegration.create_device(equipment.name, equipment.work_number, nil, 'tractor', { uuid: equipment.uuid }).execute do |c|
            c.success do |device|
              device
            end
          end
        end

        def update_device(id, equipment)
          ::Traccar::TraccarIntegration.update_device(id, equipment.name, equipment.work_number, nil, 'tractor', { uuid: equipment.uuid }).execute do |c|
            c.success do |device|
              device
            end
          end
        end

        # Writes the Traccar provider metadata directly to the row, bypassing
        # optimistic locking and Product's after_save cascade (set_initial_values,
        # build_new_phase, movements.build). The provider jsonb is metadata only —
        # no callback observes it, so skipping them is safe and avoids the
        # StaleObjectError race between Equipment.tractors snapshot and update.
        def sync_provider(equipment, traccar_id)
          equipment.update_columns(
            provider: { vendor: @vendor, name: 'device', data: { id: traccar_id.to_s, updated_at: Time.now } },
            updated_at: Time.current
          )
        end
  end
end