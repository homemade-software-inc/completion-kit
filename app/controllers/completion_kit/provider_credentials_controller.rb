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

    private

    def set_provider_credential
      @provider_credential = ProviderCredential.find(params[:id])
    end

    def provider_credential_params
      params.require(:provider_credential).permit(:provider, :api_key, :api_endpoint)
    end
  end
end
