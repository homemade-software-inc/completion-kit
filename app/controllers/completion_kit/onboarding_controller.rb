module CompletionKit
  class OnboardingController < ApplicationController
    DISMISS_COOKIE = :ck_onboarding_dismissed

    def show
      cookies.delete(DISMISS_COOKIE) if params[:reset]
      @checklist = Onboarding::Checklist.new
      return if params[:reset]

      redirect_to prompts_path if @checklist.complete? || cookies[DISMISS_COOKIE]
    end

    def dismiss
      cookies[DISMISS_COOKIE] = { value: "1", expires: 1.year.from_now, httponly: true }
      redirect_to prompts_path, notice: "Setup skipped. Pick it back up from Settings → Getting started any time."
    end

    def sample_data
      Onboarding::SampleData.install!
      redirect_to onboarding_path, notice: "Loaded a sample dataset and prompt — edit or delete them whenever."
    end
  end
end
