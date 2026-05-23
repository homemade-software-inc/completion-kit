module CompletionKit
  class OnboardingController < ApplicationController
    def show
      cookies.delete(ONBOARDING_DISMISS_COOKIE) if params[:reset]
      @checklist = Onboarding::Checklist.new
      return if params[:reset]

      redirect_to dashboard_path if workspace_ready?
    end

    def dismiss
      cookies[ONBOARDING_DISMISS_COOKIE] = {
        value: "1",
        expires: 1.year.from_now,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax
      }
      redirect_to dashboard_path, notice: "Setup skipped. Pick it back up from Settings → Getting started any time."
    end

    def sample_data
      Onboarding::SampleData.install!
      redirect_to onboarding_path, notice: "Loaded a sample dataset and prompt — edit or delete them whenever."
    end
  end
end
