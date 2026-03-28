# frozen_string_literal: true

Rails.application.routes.draw do
  concern :list do
    get :list, on: :collection
  end

  concern :unroll do
    get :unroll, on: :collection
  end

  namespace :traccar do
    resource :traccar_synchronization, only: [] do
      get :sync
    end
  end
end
