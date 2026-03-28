# Traccar

Plugin to allow integration of the data returned by Traccar into Ekylibre.
Traccar could be connected with [AOG OSFarm edition](https://github.com/osfarm/aog) or [mobile traccar app](https://www.traccar.org/client/) or [devices](https://www.traccar.org/devices/)

# References

Traccar API : https://www.traccar.org/api-reference/

Doc : https://www.traccar.org/user-management/

# Workflow

## 1 - Setup for AOG and mobile app

In case of no data, Ekylibre will setup Traccar with devices, geofences and drivers.

## 2 - Usage for AOG and mobile app

In mobile app, just use the DeviceId in your mobile app.

In AOG, select the equipment.


# Technical Workflow

### API create

Ekylibre(equipments, cultivable_zones, workers) => Traccar(devices, geofences, drivers)

AOG <= Traccar(devices, geofences, drivers)