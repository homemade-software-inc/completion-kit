module CompletionKit
  class PromptsController < ApplicationController
    include CompletionKit::TagFiltering
    before_action :set_prompt, only: [:show, :edit, :update, :destroy, :publish]

    def index
      @prompts = apply_tag_filter(Prompt.current_versions.includes(:runs, :tags).order(created_at: :desc))
    end
    
    def show
      @runs = Run.where(prompt_id: @prompt.family_versions.select(:id))
                 .includes(:prompt, :dataset, :tags, responses: :reviews)
                 .order(created_at: :desc)
                 .display_scoped
    end
    
    def new
      @prompt = Prompt.new
    end

    def edit
    end

    def create
      @prompt = Prompt.new(prompt_params)

      if @prompt.save
        redirect_to prompt_path(@prompt), notice: "Prompt version was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end
    
    def update
      if @prompt.runs.exists? && behavioral_change?
        new_prompt = @prompt.build_next_version(prompt_params.to_h)
        if new_prompt.valid?
          CompletionKit::ApplicationRecord.transaction do
            new_prompt.save!
            new_prompt.publish!
          end
          redirect_to prompt_path(new_prompt), notice: "Saved as #{new_prompt.version_label}."
        else
          @prompt.assign_attributes(prompt_params.to_h)
          @prompt.errors.merge!(new_prompt.errors)
          render :edit, status: :unprocessable_entity
        end
      elsif @prompt.update(prompt_params)
        redirect_to prompt_path(@prompt), notice: "Prompt saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end
    
    def destroy
      @prompt.destroy
      redirect_to prompts_path, notice: "Prompt version was successfully destroyed."
    end

    def publish
      @prompt.publish!
      redirect_to prompt_path(@prompt), notice: "#{@prompt.display_name} is now the published version."
    end

    private

    BEHAVIORAL_ATTRS = %w[template llm_model].freeze

    def behavioral_change?
      permitted = prompt_params
      BEHAVIORAL_ATTRS.any? do |attr|
        permitted.key?(attr) && permitted[attr].to_s != @prompt.public_send(attr).to_s
      end
    end

    def set_prompt
      @prompt = Prompt.find(params[:id])
    end
    
    def prompt_params
      params.require(:prompt).permit(
        :name,
        :description,
        :template,
        :llm_model,
        tag_names: []
      )
    end
  end
end
