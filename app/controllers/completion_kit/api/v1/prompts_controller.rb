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
          PromptServe.record!(@prompt)
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
          publish = publish_flag
          return render_error("publish must be true or false", status: :unprocessable_entity) if publish.nil?

          if @prompt.runs.exists? || (!publish && @prompt.current? && @prompt.behavioral_change?(prompt_params))
            new_prompt = @prompt.build_next_version(prompt_params.to_h)
            if new_prompt.valid?
              CompletionKit::ApplicationRecord.transaction do
                new_prompt.save!
                new_prompt.publish! if publish
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

        PUBLISH_VALUES = {"true" => true, "1" => true, "false" => false, "0" => false}.freeze

        def publish_flag
          value = params[:publish]
          return true if value.blank? && value != false

          PUBLISH_VALUES[value.to_s]
        end
      end
    end
  end
end
