module CompletionKit
  class PromptsController < ApplicationController
    before_action :set_prompt, only: [:show, :edit, :update, :destroy]
    
    def index
      @prompts = Prompt.all
    end
    
    def show
    end
    
    def new
      @prompt = Prompt.new
    end
    
    def edit
    end
    
    def create
      @prompt = Prompt.new(prompt_params)
      
      if @prompt.save
        redirect_to prompts_path, notice: 'Prompt was successfully created.'
      else
        render :new
      end
    end
    
    def update
      if @prompt.update(prompt_params)
        redirect_to prompts_path, notice: 'Prompt was successfully updated.'
      else
        render :edit
      end
    end
    
    def destroy
      @prompt.destroy
      redirect_to prompts_path, notice: 'Prompt was successfully destroyed.'
    end
    
    private
    
    def set_prompt
      @prompt = Prompt.find(params[:id])
    end
    
    def prompt_params
      params.require(:prompt).permit(:name, :description, :template, :llm_model)
    end
  end
end
