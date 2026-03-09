CompletionKit::Engine.routes.draw do
  root to: "prompts#index"
  resources :prompts do
    member do
      post :publish
      post :new_version
    end
  end

  resources :metrics
  resources :metric_groups
  resources :provider_credentials, only: [:index, :new, :create, :edit, :update]
  
  resources :test_runs do
    member do
      post :run
      post :evaluate
    end

    resources :test_results, only: [:index, :show] do
      member do
        patch :human_review
      end
    end
  end
end
