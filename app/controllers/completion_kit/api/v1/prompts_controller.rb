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
            new_prompt = @prompt.build_next_version(prompt_params.to_h)
            if new_prompt.valid?
              CompletionKit::ApplicationRecord.transaction do
                new_prompt.save!
                new_prompt.publish!
              end
              render json: new_prompt.reload
            else
              render_validation_errors(new_prompt)
            end
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
