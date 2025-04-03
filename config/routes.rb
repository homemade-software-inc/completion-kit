CompletionKit::Engine.routes.draw do
  resources :prompts
  resources :test_runs
  resources :test_results
end
