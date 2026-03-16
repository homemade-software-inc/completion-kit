module CompletionKit
  module Api
    module V1
      class ProviderCredentialsController < BaseController
        before_action :set_credential, only: [:show, :update, :destroy]

        def index
          render json: ProviderCredential.order(created_at: :desc)
        end

        def show
          render json: @credential
        end

        def create
          credential = ProviderCredential.new(credential_params)
          if credential.save
            render json: credential, status: :created
          else
            render json: {errors: credential.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @credential.update(credential_params)
            render json: @credential
          else
            render json: {errors: @credential.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @credential.destroy!
          head :no_content
        end

        private

        def set_credential
          @credential = ProviderCredential.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def credential_params
          params.permit(:provider, :api_key, :api_endpoint)
        end
      end
    end
  end
end
