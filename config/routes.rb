CompletionKit::Engine.routes.draw do
  root to: "onboarding#show"

  get "onboarding", to: "onboarding#show", as: :onboarding
  post "onboarding/dismiss", to: "onboarding#dismiss", as: :dismiss_onboarding
  post "onboarding/sample-data", to: "onboarding#sample_data", as: :onboarding_sample_data

  resources :prompts do
    member do
      post :publish
    end
  end

  resources :datasets
  resources :metrics do
    collection do
      get  "starters/:key", to: "metrics#starter_preview",  as: :starter_preview
      post "starters/:key", to: "metrics#adopt_starter",    as: :adopt_starter
      post "starters/:key/dismiss", to: "metrics#dismiss_starter", as: :dismiss_starter
    end
    member do
      post :publish_draft
      post :suggest_variants
      delete :dismiss_suggestion
      post :exclude_example
    end
  end
  resources :metric_groups
  resources :tags
  resources :dashboard_dismissals, only: [:create, :destroy]
  get "dashboard", to: "dashboard#show", as: :dashboard

  resources :runs do
    member do
      post :generate
      post :suggest
      post :retry_failures
      post :rerun
      post :regrade
      get :refresh_status
      get :compare
    end
    resources :responses, only: [:show] do
      resources :agreements, only: [:create]
    end
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
          post :rerun
          post :regrade
          get :compare
        end
        resources :responses, only: [:index, :show] do
          resources :metrics, only: [] do
            resources :agreements, only: [:index, :create]
          end
        end
      end
      resources :datasets
      resources :metrics do
        resources :metric_versions, only: [:index, :show, :destroy] do
          member do
            post :publish
          end
        end
        member do
          post :suggest_variants
        end
      end
      resources :metric_groups
      resources :tags
      resources :provider_credentials
      resources :agreements, only: [:index, :destroy]
    end
  end

  post "mcp", to: "mcp#handle"
  delete "mcp", to: "mcp#destroy"
end
