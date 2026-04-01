module CompletionKit
  class ProviderCredentialsController < ApplicationController
    before_action :set_provider_credential, only: [:edit, :update, :refresh]

    def index
      @provider_credentials = ProviderCredential.order(:provider)
    end

    def new
      @provider_credential = ProviderCredential.new(provider: params[:provider])
    end

    def create
      @provider_credential = ProviderCredential.new(provider_credential_params)

      if @provider_credential.save
        redirect_to provider_credentials_path, notice: "Provider credential was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @provider_credential.update(provider_credential_params)
        redirect_to provider_credentials_path, notice: "Provider credential was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def refresh
      ModelDiscoveryService.new(config: @provider_credential.config_hash).refresh!
      redirect_to provider_credentials_path, notice: "Models refreshed."
    end

    def refresh_all
      ProviderCredential.find_each do |cred|
        next unless %w[openai anthropic].include?(cred.provider)
        ModelDiscoveryService.new(config: cred.config_hash).refresh!
      end

      respond_to do |format|
        format.json do
          render json: {
            models_discovered: Model.count,
            for_generation: Model.for_generation.count,
            for_judging: Model.for_judging.count,
            generation_options_html: helpers.ck_model_options_html(:generation),
            judging_options_html: helpers.ck_model_options_html(:judging)
          }
        end
        format.html do
          redirect_back fallback_location: provider_credentials_path, notice: "Models refreshed."
        end
      end
    end

    private

    def set_provider_credential
      @provider_credential = ProviderCredential.find(params[:id])
    end

    def provider_credential_params
      params.require(:provider_credential).permit(:provider, :api_key, :api_endpoint)
    end
  end
end
