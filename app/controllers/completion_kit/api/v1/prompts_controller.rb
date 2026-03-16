module CompletionKit
  module Api
    module V1
      class PromptsController < BaseController
        before_action :set_prompt, only: [:show, :update, :destroy, :publish, :new_version]

        def index
          render json: Prompt.order(created_at: :desc)
        end

        def show
          render json: @prompt
        end

        def create
          prompt = Prompt.new(prompt_params)
          if prompt.save
            render json: prompt, status: :created
          else
            render json: {errors: prompt.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @prompt.update(prompt_params)
            render json: @prompt
          else
            render json: {errors: @prompt.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @prompt.destroy!
          head :no_content
        end

        def publish
          @prompt.publish!
          render json: @prompt.reload
        end

        def new_version
          version = @prompt.clone_as_new_version
          render json: version, status: :created
        end

        private

        def set_prompt
          @prompt = Prompt.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def prompt_params
          params.permit(:name, :description, :template, :llm_model)
        end
      end
    end
  end
end
