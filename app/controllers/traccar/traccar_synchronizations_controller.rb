require 'securerandom'

module Traccar
  class TraccarSynchronizationsController < Backend::BaseController
    def sync
      TraccarFetchUpdateCreateJob.perform_later(user_id: params[:user_id])
      notify_success(:traccar_synchronizing.tl)

      redirect_to backend_ride_sets_path
    end
  end
end
