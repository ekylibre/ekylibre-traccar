module Traccar
  class GrabPosition

    # Crumb > Ride > RideSet
    # Ride > CultivableZone
    # RideSetEquipment > RideSet
    ACCURACY_TOLERANCE = 100.0  # meters

    def initialize
      @from = (Time.now - 2.months).utc.iso8601
      @to = Time.now.utc.iso8601
      @vendor = EkylibreTraccar::VENDOR
      @equipments = Equipment.tractors.where.not(provider: nil).of_provider_vendor(@vendor)
      @trip_count = 0
    end

    def get_positions
      @equipments.each do |equipment|
        # get last sync positions from Ekylibre in crumbs
        device_id = equipment.provider_data[:id].to_i
        last_sync = find_last_crumb(device_id)
        @from = last_sync.read_at.utc.iso8601 if last_sync.present?
        # get last positions from Traccar and store in crumbs in Ekylibre
        traccar_positions = fetch_positions(device_id, @from, @to)
        traccar_positions.each do |traccar_position|
          create_crumb(traccar_position, equipment.id)
        end
        # get last trip from by day (API issue) Traccar and store in ride_sets in Ekylibre
        @from.to_date.upto(@to.to_date) do |day|
          start = day.beginning_of_day.utc.iso8601
          stop = day.end_of_day.utc.iso8601
          traccar_trip_equipment_count = 0
          traccar_trips = fetch_trips(device_id, start, stop)
          traccar_trips.each do |traccar_trip|
            ride_set_id = create_ride_set(traccar_trip, equipment.id)
            if ride_set_id
              create_ride(ride_set_id, traccar_trip, equipment.id) 
              traccar_trip_equipment_count += 1
            end
          end
          @trip_count += traccar_trip_equipment_count
        end
      end
      @trip_count
    end
    

    private

        def fetch_positions(device_id, from, to)
          ::Traccar::TraccarIntegration.fetch_positions(device_id, from, to).execute do |c|
            c.success do |positions|
              positions
            end
          end
        end

        def fetch_trips(device_id, from, to)
          ::Traccar::TraccarIntegration.fetch_trips(device_id, from, to).execute do |c|
            c.success do |trips|
              trips
            end
          end
        end

        def find_last_crumb(device_id)
          Crumb.of_provider_vendor(@vendor)
               .of_provider_data(:device_id, device_id.to_s)
               .reorder(:read_at)
               .last
        end

        def find_ride_set_by_position_id(position_id, device_id)
          RideSet.of_provider_vendor(@vendor)
                 .of_provider_data(:device_id, device_id.to_s)
                 .of_provider_data(:start_position_id, position_id.to_s)
                 .last
        end

        def find_ride_by_position_id(position_id, device_id)
          Ride.of_provider_vendor(@vendor)
              .of_provider_data(:device_id, device_id.to_s)
              .of_provider_data(:start_position_id, position_id.to_s)
              .last
        end

        def create_ride_set(traccar_trip, equipment_id)
          started_at = Time.parse(traccar_trip[:startTime])
          stopped_at = Time.parse(traccar_trip[:endTime])
          nature = 'work'
          duration = (traccar_trip[:duration] / 1000).to_i.seconds
          distance = (traccar_trip[:distance] / 1000).to_d.round(2)
          start_position_id = traccar_trip[:startPositionId]
          #  "startTime": "2025-05-14T12:45:20.000+00:00",
          #  "endTime": "2025-05-14T12:54:38.000+00:00",
          unless find_ride_set_by_position_id(start_position_id, traccar_trip[:deviceId])
            ride_set = RideSet.create!(
              nature: nature,
              duration: duration,
              road: distance,
              started_at: started_at,
              stopped_at: stopped_at,
              provider: { vendor: @vendor, name: 'trip',
                          data: { device_id: traccar_trip[:deviceId].to_s, start_position_id: traccar_trip[:startPositionId].to_s }
                        }      
            )
            # set main equipment to ride set
            ride_set_equipment = RideSetEquipment.create!(
                ride_set: ride_set,
                product_id: equipment_id,
                nature: 'main',
                provider: { vendor: @vendor, name: 'trip',
                          data: { device_id: traccar_trip[:deviceId].to_s, start_position_id: traccar_trip[:startPositionId].to_s }
                        }
              )
            ride_set.id
          end
        end

        def create_ride(ride_set_id, traccar_trip, equipment_id)
          started_at = Time.parse(traccar_trip[:startTime])
          stopped_at = Time.parse(traccar_trip[:endTime])
          nature = 'work'
          distance = (traccar_trip[:distance] / 1000).to_d.round(2)
          duration = (traccar_trip[:duration] / 1000).to_i.seconds
          start_position_id = traccar_trip[:startPositionId]
          #  "startTime": "2025-05-14T12:45:20.000+00:00",
          #  "endTime": "2025-05-14T12:54:38.000+00:00",
          unless find_ride_by_position_id(start_position_id, traccar_trip[:deviceId])
            ride = Ride.create!(
              ride_set_id: ride_set_id,
              nature: nature,
              duration: duration,
              distance_km: distance,
              started_at: started_at,
              stopped_at: stopped_at,
              provider: { vendor: @vendor, name: 'trip',
                          data: { device_id: traccar_trip[:deviceId].to_s, start_position_id: start_position_id.to_s }
                        }          
            )
            # get first and last crumb from trip
            first_crumb = Crumb.of_provider_vendor(@vendor).of_provider_data(:id, start_position_id.to_s).first
            last_crumb = Crumb.of_provider_vendor(@vendor).of_provider_data(:id, traccar_trip[:endPositionId].to_s).first
            crumb_ids = [*first_crumb.id..last_crumb.id]
            crumbs = Crumb.of_provider_vendor(@vendor).where(id: crumb_ids).where("accuracy <= ?", ACCURACY_TOLERANCE).reorder(:read_at)
            crumbs.update_all(ride_id: ride.id)
            geolocate_crumbs = crumbs.pluck(:geolocation)
            # if crumbs is one, double to make line
            fixed_geolocate_crumbs = if geolocate_crumbs.size > 1
                          geolocate_crumbs
                        else
                          geolocate_crumbs << geolocate_crumbs.first
                          geolocate_crumbs
                        end
            line = ::Charta.make_line(fixed_geolocate_crumbs)
            ride.update!(shape: line)
            # update ride_set shape
            ride_set = RideSet.find(ride_set_id)
            shape_line_with_buffer = line.simplify(0.0001).to_rgeo.buffer(1)
            ride_set.update!(shape: shape_line_with_buffer)
            # set cultivable_zone from geofence_ids if present in first crumb from AOG attributes
            geofence_ids_from_crumb = first_crumb.provider_data[:geofence_ids]
            czs = CultivableZone.of_provider_vendor(@vendor).of_provider_data(:id, geofence_ids_from_crumb.first.to_s) if geofence_ids_from_crumb.any?
            ride.update!(cultivable_zone_id: czs.first.id) if czs.present?
            # set tool if present in first crumb from AOG attributes
            tool_id_from_crumb = first_crumb.provider_data[:tool_work_number]
            tool = Equipment.find_by(work_number: tool_id_from_crumb) if tool_id_from_crumb.present?
            if tool.present?
              ride_set_equipment = RideSetEquipment.create!(
                  ride_set: ride_set,
                  product_id: tool.id,
                  nature: 'additional',
                  provider: { vendor: @vendor, name: 'trip',
                            data: { tool_work_number: tool_id_from_crumb.to_s, start_position_id: start_position_id.to_s }
                        }
                )
            end
          end
        end

        def create_crumb(traccar_position, equipment_id)
          geolocation_crumb = Charta.new_point(traccar_position[:latitude], traccar_position[:longitude]).to_rgeo
          nature_crumb = if traccar_position[:attributes][:motion]
                           'point'
                         else
                           'stop'
                         end
          # agricultural informations
          metadata = {}

          crumb = Crumb.create!(
            nature: nature_crumb,
            device_uid: equipment_id.to_s,
            accuracy: traccar_position[:accuracy].to_d.round(2),
            geolocation: geolocation_crumb,
            metadata: metadata, 
            read_at: Time.parse(traccar_position[:fixTime]),
            provider: { vendor: @vendor, name: 'position',
                        data: { id: traccar_position[:id].to_s,
                                device_id: traccar_position[:deviceId].to_s,
                                geofence_ids: (traccar_position[:geofenceIds].present? ? traccar_position[:geofenceIds] : []),
                                working_width: (traccar_position[:attributes][:workingWidth].present? ? traccar_position[:attributes][:workingWidth] : nil),
                                is_working: (traccar_position[:attributes][:isWorking].present? ? traccar_position[:attributes][:isWorking] : nil),
                                tool_name: (traccar_position[:attributes][:toolName].present? ? traccar_position[:attributes][:toolName] : nil),
                                tool_work_number: (traccar_position[:attributes][:toolUniqueId].present? ? traccar_position[:attributes][:toolUniqueId] : nil),
                                speed: traccar_position[:speed].to_d.round(2),
                                distance: traccar_position[:attributes][:distance].to_d.round(2),
                                altitude: traccar_position[:altitude].to_d.round(2)
                              }
                      }
          )
        end
  end
end