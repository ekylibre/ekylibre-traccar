class TraccarFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  def perform(user_id: nil)
    Preference.set!(:traccar_fetch_job_running, true, :boolean)
    user = User.find(user_id) if user_id
    begin
      # create user link for connecting directly to Traccar
      Traccar::ManageToken.new.create_user_link
      # find and create or update equipments in Traccar from tractor in Ekylibre
      Traccar::ManageEquipment.new.update_devices
      # find and create or update geofences in Traccar from cultivable zones in Ekylibre
      Traccar::ManageGeofence.new.update_geofences
      # get positions in Traccar and store in crumbs in Ekylibre
      @count = Traccar::GrabPosition.new.get_positions
      # get trips in Traccar and store in ride_sets in Ekylibre
      user.notifications.create!(success_traccar_fetch_params) if user.present?
      Preference.set!(:traccar_fetch_job_running, false, :boolean)
    rescue StandardError => error
      Preference.set!(:traccar_fetch_job_running, false, :boolean)
      Rails.logger.error $ERROR_INFO
      Rails.logger.error $ERROR_INFO.backtrace.join("\n")
      ExceptionNotifier.notify_exception($ERROR_INFO, data: { message: error })
      @error = error.message
      user.notifications.create!(errors_traccar_fetch_params) if user.present?
    end
  end

  private

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
