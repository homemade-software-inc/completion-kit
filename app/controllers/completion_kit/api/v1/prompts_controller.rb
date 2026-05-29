module CompletionKit
  module Api
    module V1
      class PromptsController < BaseController
        before_action :set_prompt, only: [:show, :update, :destroy, :publish]

        def index
          scope = Prompt.includes(:tags)
          scope = filter_by_tags(scope)
          render json: paginate(scope.order(created_at: :desc))
        end

        def show
          render json: @prompt
        end

        def create
          prompt = Prompt.new(prompt_params)
          if prompt.save
            render json: prompt, status: :created
          else
            render_validation_errors(prompt)
          end
        end

        def update
          if @prompt.runs.exists?
            new_prompt = @prompt.clone_as_new_version(prompt_params.except(:tag_names).to_h)
            new_prompt.publish!
            new_prompt.update!(tag_names: prompt_params[:tag_names]) if prompt_params.key?(:tag_names)
            render json: new_prompt.reload
          elsif @prompt.update(prompt_params)
            render json: @prompt
          else
            render_validation_errors(@prompt)
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

        private

        def set_prompt
          @prompt = if params[:id].to_s.match?(/\A\d+\z/)
                      Prompt.find(params[:id])
                    else
                      Prompt.current_for(params[:id])
                    end
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def prompt_params
          params.permit(:name, :description, :template, :llm_model, tag_names: [])
        end
      end
    end
  end
end
