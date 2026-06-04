# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Rails engine packaged as a gem (`ekylibre-traccar`) that plugs into the [Ekylibre](https://ekylibre.com) farm-management application. It synchronizes data between Ekylibre and a [Traccar](https://www.traccar.org) server (open-source GPS tracking) so that tractors, fields, and worker positions stay aligned across both systems. The Traccar server is typically fed by the [AOG OSFarm](https://github.com/osfarm/aog) agricultural autosteer or the Traccar mobile/device clients.

This plugin is **not standalone** — it is mounted inside a host Ekylibre Rails app and depends on Ekylibre models (`Equipment`, `CultivableZone`, `Crumb`, `Ride`, `RideSet`, `RideSetEquipment`, `Integration`, `Preference`, `User`, etc.), the `ActionIntegration::Base` framework, the `Ekylibre::View::Addon` extension point, and the `Charta` geometry library. None of these live in this repo — read the host application to understand them.

## Domain mapping (essential context)

The whole plugin exists to keep these objects in sync. Every service is structured around this mapping:

| Ekylibre              | Traccar          |
|-----------------------|------------------|
| `Equipment` (tractor) | `device`         |
| `CultivableZone`      | `geofence`       |
| `Worker`              | `driver`         |
| `Crumb`               | `position`       |
| `RideSet` + `Ride`    | `trip`           |
| `Campaign`            | `calendar`       |

Sync is bidirectional in spec but the implemented direction is **Ekylibre → Traccar** for create/update of devices and geofences, and **Traccar → Ekylibre** for positions and trips. The `uuid` of an Ekylibre record is stored in the Traccar object's `attributes.uuid` field — this is the join key used to detect "already synced" objects. When a Traccar object has no `uuid` attribute but matches by `uniqueId == work_number`, the plugin "adopts" it (updates it with the uuid). On the Ekylibre side, the Traccar id is stored in `provider: { vendor: 'traccar', name: '<kind>', data: { id: ... } }` via the polymorphic provider field — most service queries use `of_provider_vendor('traccar')` / `of_provider_data(:key, value)` scopes that come from the host app.

## Architecture

Three layers, all under `app/`:

1. **`app/integrations/traccar/traccar_integration.rb`** — the HTTP client. Subclass of `ActionIntegration::Base` (host-provided). Declares credentials via `authenticate_with :check { parameter ... }`, lists callable endpoints via `calls :fetch_positions, ...`, and exposes one method per Traccar REST endpoint (`fetch_*`, `create_*`, `update_*`, `create_token`, `check`). Auth is HTTP Basic from `integration.parameters['email']` / `['password']`; `base_url` builds `<server_url>/api/<endpoint>`. The integration is invoked by callers as `Traccar::TraccarIntegration.fetch_devices.execute { |c| c.success { |x| ... } }` — that `.execute` + success-block pattern is the host's `ActionIntegration` convention, not Ruby blocks returning values.

2. **`app/services/traccar/*.rb`** — orchestration. One class per concern, each instantiates the integration and reconciles records:
   - `ManageToken#create_user_link` — rotates a 7-day session token and stores the resulting `web_url` (`<server>/?token=...`) on the Integration record so the UI can deep-link into the Traccar web app.
   - `ManageEquipment#update_devices` — iterates `Equipment.tractors`, matches by `uuid` attr, adopts by `work_number`, otherwise creates.
   - `ManageGeofence#update_geofences` — iterates `CultivableZone.all`, matches by `uuid`, updates or creates. Geofence area is `cz.shape_to_wkt_polygon(true)`.
   - `GrabPosition#get_positions` — for each provider-tagged tractor: pulls positions since the last synced crumb (`fetch_positions`), creates `Crumb` rows, then walks day-by-day pulling trips (`fetch_trips`) and creating `RideSet` + `Ride` + `RideSetEquipment` rows. Each `Ride.shape` is built by joining the trip's crumbs (filtered by `ACCURACY_TOLERANCE = 100.0` meters) via `Charta.make_line`; the `RideSet.shape` is a 1-meter buffer around the simplified line. The day-by-day loop is a workaround for a Traccar `reports/trips` API limitation noted inline. Cross-data enrichment: the first crumb's `geofence_ids` provider data links the ride to a `CultivableZone`, and its `tool_work_number` attaches a secondary tool `Equipment` to the `RideSet` as an `'additional'` `RideSetEquipment`. The method returns `@trip_count`.

3. **`app/jobs/traccar_fetch_update_create_job.rb`** — the orchestrator. Runs all four services in order, sets/clears the `traccar_fetch_job_running` boolean `Preference` as a UI lock, and notifies the triggering user on success or failure (`success_traccar_fetch_params` links to `/backend/ride_sets`).

The `Engine` (`lib/ekylibre-traccar/engine.rb`) wires three things into the host: an asset (`integrations/traccar.png`), a toolbar partial (`Ekylibre::View::Addon.add(:extensions_content_top, 'backend/ride_sets/sync_traccar_toolbar', to: 'backend/ride_sets#index')`), and the integration lifecycle hooks — `on_check_success` fires the job once after credential validation, and `run every: :day` schedules a daily sync **only if** an `Integration` with `nature: 'traccar'` exists.

Manual trigger flow: the toolbar partial renders a "Synchronisation" button → `GET /traccar/traccar_synchronization/sync` → `Traccar::TraccarSynchronizationsController#sync` → `TraccarFetchUpdateCreateJob.perform_later(user_id: current_user.id)` → redirect to `/backend/ride_sets` with a flash. The button is disabled while the `traccar_fetch_job_running` preference is true.

## Development

This is a Rails engine gem with no own test suite, build script, lint config, or CI. There are no commands to "build" or "test" inside this repo. To exercise the plugin, the host Ekylibre app must include it via `Gemfile` (path or git source) and provide a configured `Integration` record with `nature: 'traccar'` and `parameters` containing `server_url`, `email`, `password`.

Version is hand-bumped in `lib/ekylibre-traccar/version.rb`.

## Conventions worth preserving

- File/module naming uses dash-prefixed paths (`lib/ekylibre-traccar/...`) — the host loads this gem expecting that layout; do not switch to `ekylibre_traccar/`.
- Every service method that calls the integration uses the same `.execute do |c| c.success do |x| x end end` wrapper. Keep that shape — `success` is the only callback wired up.
- The vendor string is centralized as `EkylibreTraccar::VENDOR = 'traccar'`. Use it (not a string literal) anywhere you write to a `provider:` field or scope by `of_provider_vendor(...)`.
- Locale keys live under `config/locales/{eng,fra}/action.yml`. The `eng/action.yml` file currently contains many `samsys_*` keys copied from a sibling plugin; only the `traccar_*` keys and the generic ride labels are actually referenced from this plugin's views/jobs.
