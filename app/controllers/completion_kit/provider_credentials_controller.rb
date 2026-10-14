module CompletionKit
  class ProviderCredentialsController < ApplicationController
    before_action :set_provider_credential, only: [:edit, :update, :refresh, :destroy]

    def index
      @provider_credentials = ProviderCredential.order(:provider)
    end

    def statuses
      @provider_credentials = ProviderCredential.order(:provider)
      respond_to { |format| format.turbo_stream }
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
      attributes = provider_credential_update_params
      remove = attributes[:remove_api_key] == "1"
      @remove_api_key = remove && attributes[:api_key].blank?

      if @provider_credential.update(with_api_key_choice(attributes.except(:remove_api_key), remove: remove))
        redirect_to provider_credentials_path, notice: "Provider credential was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @provider_credential.destroy
        redirect_to provider_credentials_path, notice: "#{@provider_credential.display_provider} provider was removed."
      else
        redirect_to provider_credentials_path, alert: @provider_credential.errors.full_messages.to_sentence
      end
    end

    def refresh
      @provider_credential.update_columns(discovery_status: "discovering", discovery_current: 0, discovery_total: 0)
      @provider_credential.reload
      @provider_credential.broadcast_discovery_progress
      ModelDiscoveryJob.perform_later(@provider_credential.id, force: true)
      head :ok
    end

    def refresh_all
      ProviderCredential.find_each do |cred|
        cred.update_columns(discovery_status: "discovering", discovery_current: 0, discovery_total: 0)
        cred.reload
        cred.broadcast_discovery_progress
        ModelDiscoveryJob.perform_later(cred.id, force: true)
      end

      head :ok
    end

    private

    def set_provider_credential
      @provider_credential = ProviderCredential.find(params[:id])
    end

    def provider_credential_params
      params.require(:provider_credential).permit(:provider, :api_key, :api_endpoint, :api_version)
    end

    def provider_credential_update_params
      params.require(:provider_credential).permit(:provider, :api_key, :api_endpoint, :api_version, :remove_api_key)
    end

    def with_api_key_choice(attributes, remove:)
      if attributes[:api_key].present?
        attributes
      elsif remove
        attributes.merge(api_key: nil)
      else
        attributes.except(:api_key)
      end
    end
  end
end
