class TraccarFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  def perform(user_id: nil)
    Preference.set!(:traccar_fetch_job_running, true, :boolean)
    user = User.find(user_id) if user_id
    @errors = []
    @count = 0

    run_step('manage_token')     { Traccar::ManageToken.new.create_user_link }
    run_step('manage_equipment') { Traccar::ManageEquipment.new.update_devices }
    run_step('manage_geofence')  { Traccar::ManageGeofence.new.update_geofences }
    @count = run_step('grab_position') { Traccar::GrabPosition.new.get_positions } || 0

    if user.present?
      if @errors.any?
        @error = @errors.join('; ')
        user.notifications.create!(errors_traccar_fetch_params)
      else
        user.notifications.create!(success_traccar_fetch_params)
      end
    end
  ensure
    Preference.set!(:traccar_fetch_job_running, false, :boolean)
  end

  private

    def run_step(name)
      yield
    rescue StandardError => error
      Rails.logger.error "[Traccar] step #{name} failed: #{error.class}: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      ExceptionNotifier.notify_exception(error, data: { traccar_step: name })
      @errors << "#{name}: #{error.message}"
      nil
    end

    def errors_traccar_fetch_params
      {
        message: :failed_traccar_fetch_params.tl,
        level: :error,
        interpolations: { message: @error }
      }
    end

    def success_traccar_fetch_params
      {
        message: :correct_traccar_fetch_params.tl,
        level: :success,
        target_url: '/backend/ride_sets',
        interpolations: { count: @count.to_s }
      }
    end

end
