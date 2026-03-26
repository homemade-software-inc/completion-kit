module CompletionKit
  class ApiReferenceController < ApplicationController
    def index
      @published_prompts = Prompt.current_versions.order(name: :asc)
      @token = CompletionKit.config.api_token
      @base_url = request.base_url + request.script_name
    end
  end
end
