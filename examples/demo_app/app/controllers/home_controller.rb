class HomeController < ApplicationController
  def index
    @prompt_count = CompletionKit::Prompt.count
    @test_run_count = CompletionKit::TestRun.count
  end
end
