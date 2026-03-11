class HomeController < ApplicationController
  def index
    @prompt_count = CompletionKit::Prompt.count
    @run_count = CompletionKit::Run.count
  end
end
