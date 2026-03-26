Rails.application.routes.draw do
  root to: "home#index"
  mount CompletionKit::Engine => "/completion_kit"
end
