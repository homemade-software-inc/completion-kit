module CompletionKit
  class PromptsController < ApplicationController
    before_action :set_prompt, only: [:show, :edit, :update, :destroy, :publish, :new_version]
    
    def index
      @prompts = Prompt.current_versions.order(created_at: :desc)
    end
    
    def show
      @family_versions = @prompt.family_versions
      @runs = @prompt.runs.includes(:dataset, :responses).order(created_at: :desc)
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
        redirect_to edit_prompt_path(new_prompt), notice: "Created #{new_prompt.version_label}. The previous version is unchanged because it already has runs."
      elsif @prompt.update(prompt_params)
        redirect_to prompt_path(@prompt), notice: "Prompt version was successfully updated."
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

    def new_version
      new_prompt = @prompt.clone_as_new_version
      redirect_to edit_prompt_path(new_prompt), notice: "Drafted #{new_prompt.display_name}. Review it, then publish when ready."
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
