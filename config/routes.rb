CompletionKit::Engine.routes.draw do
  root to: "onboarding#show"

  get "onboarding", to: "onboarding#show", as: :onboarding
  post "onboarding/dismiss", to: "onboarding#dismiss", as: :dismiss_onboarding

  resources :prompts do
    member do
      post :publish
    end
  end

  resources :datasets
  resources :metrics
  resources :metric_groups
  resources :tags

  resources :runs do
    member do
      post :generate
      post :suggest
      post :retry_failures
      post :rerun
      get :refresh_status
    end
    resources :responses, only: [:show]
  end

  resources :suggestions, only: [:show] do
    member do
      post :apply
    end
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
          post :retry_failures
        end
        resources :responses, only: [:index, :show]
      end
      resources :datasets
      resources :metrics
      resources :metric_groups
      resources :tags
      resources :provider_credentials
    end
  end

  post "mcp", to: "mcp#handle"
  delete "mcp", to: "mcp#destroy"
end
