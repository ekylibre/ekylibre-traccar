module EkylibreTraccar
  class Engine < ::Rails::Engine
    initializer 'ekylibre_traccar.assets.precompile' do |app|
      app.config.assets.precompile += %w[integrations/traccar.png]
    end

    initializer :ekylibre_traccar_i18n do |app|
      app.config.i18n.load_path += Dir[EkylibreTraccar::Engine.root.join('config', 'locales', '**', '*.yml')]
    end

    initializer 'ekylibre-traccar.extend_toolbar' do |_app|
      Ekylibre::View::Addon.add(:extensions_content_top, 'backend/ride_sets/sync_traccar_toolbar', to: 'backend/ride_sets#index')
    end

    initializer :ekylibre_traccar_integration do
      Traccar::TraccarIntegration.on_check_success do
        TraccarFetchUpdateCreateJob.perform_later
      end

      Traccar::TraccarIntegration.run every: :day do
        if Integration.find_by(nature: 'traccar').present?
          TraccarFetchUpdateCreateJob.perform_now
        end
      end
    end
  end
end
