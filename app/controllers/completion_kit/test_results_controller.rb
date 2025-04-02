module CompletionKit
  class TestResultsController < ApplicationController
    before_action :set_test_run
    before_action :set_test_result, only: [:show]
    
    def index
      sort_param = params[:sort] || 'score_desc'
      filter_param = params[:filter] || 'all'
      
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
      
      @test_results = case filter_param
                      when 'high_quality'
                        @test_results.where('quality_score >= ?', 80)
                      when 'medium_quality'
                        @test_results.where('quality_score >= ? AND quality_score < ?', 50, 80)
                      when 'low_quality'
                        @test_results.where('quality_score < ?', 50)
                      when 'no_score'
                        @test_results.where(quality_score: nil)
                      else
                        @test_results
                      end
    end
    
    def show
      # Comparison with expected output if available
      if @test_result.expected_output.present?
        @comparison = {
          similarity: calculate_similarity(@test_result.output_text, @test_result.expected_output),
          differences: highlight_differences(@test_result.output_text, @test_result.expected_output)
        }
      end
    end
    
    private
    
    def set_test_run
      @test_run = TestRun.find(params[:test_run_id])
    end
    
    def set_test_result
      @test_result = @test_run.test_results.find(params[:id])
    end
    
    # Simple similarity calculation (percentage of matching words)
    def calculate_similarity(text1, text2)
      return 0 if text1.blank? || text2.blank?
      
      words1 = text1.downcase.split(/\W+/).reject(&:empty?)
      words2 = text2.downcase.split(/\W+/).reject(&:empty?)
      
      common_words = (words1 & words2).size
      total_words = [words1.size, words2.size].max
      
      total_words > 0 ? (common_words.to_f / total_words * 100).round(2) : 0
    end
    
    # Simple difference highlighting (placeholder for more sophisticated diff)
    def highlight_differences(text1, text2)
      "Output and expected output differ in content and structure."
    end
  end
end
