class TraccarFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  def perform
    Preference.set!(:traccar_fetch_job_running, true, :boolean)
    begin
      Traccar::TraccarIntegration.fetch_users.execute do |c|
        c.success do |list|
          puts list.inspect.red
        end
      end
    rescue StandardError => error
      Preference.set!(:traccar_fetch_job_running, false, :boolean)
      Rails.logger.error $ERROR_INFO
      Rails.logger.error $ERROR_INFO.backtrace.join("\n")
      ExceptionNotifier.notify_exception($ERROR_INFO, data: { message: error })
      @error = error.message
    end
    Preference.set!(:traccar_fetch_job_running, false, :boolean)
  end

  private

    def errors_samsys_fetch_params
      {
        message: :failed_samsys_fetch_params.tl,
        level: :error,
        interpolations: { message: @error }
      }
    end

    def correct_samsys_fetch_params
      {
        message: :correct_samsys_fetch_params.tl,
        level: :success,
        target_url: '/backend/ride_sets',
        interpolations: { count: @count.to_s }
      }
    end

end
