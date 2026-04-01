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
      @provider_credential.update_columns(discovery_status: "discovering", discovery_current: 0, discovery_total: 0)
      @provider_credential.broadcast_discovery_progress
      ModelDiscoveryJob.perform_later(@provider_credential.id)
      head :ok
    end

    def refresh_all
      ProviderCredential.find_each do |cred|
        ModelDiscoveryJob.perform_later(cred.id)
      end

      respond_to do |format|
        format.json { render json: { status: "discovery_started" } }
        format.html { redirect_back fallback_location: provider_credentials_path, notice: "Model discovery started." }
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
