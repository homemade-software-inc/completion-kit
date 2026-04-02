module CompletionKit
  class PromptsController < ApplicationController
    before_action :set_prompt, only: [:show, :edit, :update, :destroy, :publish]
    
    def index
      @prompts = Prompt.current_versions.includes(:runs).order(created_at: :desc)
    end
    
    def show
      @runs = Run.where(prompt_id: @prompt.family_versions.select(:id))
                 .includes(:prompt, :dataset, responses: :reviews)
                 .order(created_at: :desc)
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
      if @prompt.runs.exists?
        new_prompt = @prompt.clone_as_new_version(prompt_params.to_h)
        new_prompt.publish!
        redirect_to prompt_path(new_prompt), notice: "Saved as #{new_prompt.version_label}."
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
      redirect_to prompt_path(@prompt), notice: "#{@prompt.display_name} is now the current version."
    end

    private
    
    def set_prompt
      @prompt = Prompt.find(params[:id])
    end
    
    def prompt_params
      params.require(:prompt).permit(
        :name,
        :description,
        :template,
        :llm_model
      )
    end
  end
end
