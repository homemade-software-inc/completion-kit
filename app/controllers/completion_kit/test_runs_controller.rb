module CompletionKit
  class TestRunsController < ApplicationController
    before_action :set_test_run, only: [:show, :edit, :update, :destroy, :run, :evaluate]
    
    def index
      @test_runs = TestRun.includes(:prompt, :test_results).order(created_at: :desc)
    end
    
    def show
      sort_param = params[:sort] || 'score_desc'
      
      @test_results = case sort_param
                      when 'score_desc'
                        @test_run.test_results.order(quality_score: :desc)
                      when 'score_asc'
                        @test_run.test_results.order(quality_score: :asc)
                      when 'created_desc'
                        @test_run.test_results.order(created_at: :desc)
                      when 'created_asc'
                        @test_run.test_results.order(created_at: :asc)
                      else
                        @test_run.test_results.order(quality_score: :desc)
                      end
    end
    
    def new
      @test_run = TestRun.new(prompt_id: params[:prompt_id])
      @prompts = Prompt.order(:name)
    end
    
    def edit
      @prompts = Prompt.order(:name)
    end
    
    def create
      @test_run = TestRun.new(test_run_params)
      @prompts = Prompt.order(:name)
      
      # Validate CSV data before saving
      if @test_run.valid? && @test_run.process_csv_data && @test_run.save
        redirect_to test_runs_path, notice: 'Test run was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end
    
    def update
      @prompts = Prompt.order(:name)
      @test_run.assign_attributes(test_run_params)

      # Validate CSV data before updating
      if @test_run.valid? && @test_run.process_csv_data && @test_run.save
        redirect_to test_runs_path, notice: 'Test run was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end
    
    def destroy
      @test_run.destroy
      redirect_to test_runs_path, notice: 'Test run was successfully destroyed.'
    end
    
    def run
      if @test_run.run_tests
        redirect_to @test_run, notice: 'Test run has been processed successfully.'
      else
        redirect_to @test_run, alert: @test_run.errors.full_messages.to_sentence.presence || 'Failed to process test run. Please check the configuration and try again.'
      end
    end
    
    def evaluate
      results_count = @test_run.evaluate_results
      
      if results_count > 0
        redirect_to @test_run, notice: "Successfully evaluated #{results_count} test results."
      else
        redirect_to @test_run, alert: 'Failed to evaluate test results. Please check the configuration and try again.'
      end
    end
    
    private
    
    def set_test_run
      @test_run = TestRun.find(params[:id])
    end
    
    def test_run_params
      params.require(:test_run).permit(:prompt_id, :name, :csv_data)
    end
  end
end
