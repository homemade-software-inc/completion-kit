CompletionKit::Engine.routes.draw do
  root to: "prompts#index"

  resources :prompts do
    member do
      post :publish
      post :new_version
    end
  end

  resources :datasets
  resources :metrics
  resources :criteria, controller: "criteria"

  resources :runs do
    member do
      post :generate
      post :judge
    end
    resources :responses, only: [:show]
  end

  resources :provider_credentials, only: [:index, :new, :create, :edit, :update]
end
