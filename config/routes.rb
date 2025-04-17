CompletionKit::Engine.routes.draw do
  resources :prompts
  
  resources :test_runs do
    member do
      post :run
      post :evaluate
    end
  end
  
  resources :test_results
end
