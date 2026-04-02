CompletionKit::Engine.routes.draw do
  root to: "prompts#index"

  resources :prompts do
    member do
      post :publish
    end
  end

  resources :datasets
  resources :metrics
  resources :criteria, controller: "criteria"

  resources :runs do
    member do
      post :generate
      post :judge
      get :suggestion
      post :suggest
    end
    resources :responses, only: [:show]
  end

  resources :provider_credentials, only: [:index, :new, :create, :edit, :update] do
    post :refresh, on: :member
  end
  post "refresh_models", to: "provider_credentials#refresh_all", as: :refresh_models

  get "api_reference", to: "api_reference#index", as: :api_reference

  namespace :api do
    namespace :v1 do
      resources :prompts do
        member do
          post :publish
        end
      end
      resources :runs do
        member do
          post :generate
          post :judge
        end
        resources :responses, only: [:index, :show]
      end
      resources :datasets
      resources :metrics
      resources :criteria, controller: "criteria"
      resources :provider_credentials
    end
  end

  post "mcp", to: "mcp#handle"
  delete "mcp", to: "mcp#destroy"
end
