module CompletionKit
  module McpTools
    module Prompts
      extend Base

      TOOLS = {
        "prompts_list" => {
          description: "List all prompts",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "prompts_get" => {
          description: "Get a prompt by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer", description: "Prompt ID"}}, required: ["id"]},
          handler: :get
        },
        "prompts_create" => {
          description: "Create a prompt",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, description: {type: "string"},
              template: {type: "string"}, llm_model: {type: "string"},
              tag_names: {type: "array", items: {type: "string"}}
            },
            required: ["name", "template", "llm_model"]
          },
          handler: :create
        },
        "prompts_update" => {
          description: "Update a prompt. If the prompt already has runs, this creates a new DRAFT version (current=false) rather than editing in place or publishing — promote it with prompts_publish — so an agent's edits don't go live without a gate. If it has no runs, it is updated in place.",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, description: {type: "string"},
              template: {type: "string"}, llm_model: {type: "string"},
              tag_names: {type: "array", items: {type: "string"}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "prompts_delete" => {
          description: "Delete a prompt",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "prompts_publish" => {
          description: "Publish a prompt version, making it the current version",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :publish
        },
        "prompts_suggest_improvement" => {
          description: "Suggest an improved version of a prompt, grounded in a run's test results and judge feedback. Analyzes the run's responses, scores, and reviews, then returns reasoning plus a rewritten template (preserving {{variables}}) and persists it as a Suggestion. Requires a run that has a prompt (not a judge-only run).",
          inputSchema: {
            type: "object",
            properties: {run_id: {type: "integer", description: "The run whose results ground the improvement."}},
            required: ["run_id"]
          },
          handler: :suggest_improvement
        },
      }.freeze

      def self.list(_args)
        text_result(Prompt.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Prompt.find(args["id"]).as_json)
      end

      def self.create(args)
        prompt = Prompt.new(args.slice("name", "description", "template", "llm_model"))
        prompt.tag_names = args["tag_names"] if args.key?("tag_names")
        if prompt.save
          text_result(prompt.reload.as_json)
        else
          error_result(prompt.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        prompt = Prompt.find(args["id"])
        attrs = args.except("id").slice("name", "description", "template", "llm_model")
        if prompt.runs.exists?
          new_prompt = prompt.clone_as_new_version(attrs)
          new_prompt.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
          text_result(new_prompt.reload.as_json)
        elsif prompt.update(attrs)
          prompt.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
          text_result(prompt.reload.as_json)
        else
          error_result(prompt.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Prompt.find(args["id"]).destroy!
        text_result("Prompt #{args["id"]} deleted")
      end

      def self.publish(args)
        prompt = Prompt.find(args["id"])
        prompt.publish!
        text_result(prompt.reload.as_json)
      end

      def self.suggest_improvement(args)
        run = Run.find(args["run_id"])
        return error_result("Judge-only runs don't have a prompt to improve.") if run.prompt.nil?

        result = PromptImprovementService.new(run).suggest
        return error_result("The model didn't return a usable rewrite.") if result["suggested_template"].blank?

        validation = PromptImprovementValidator.new(run, result["suggested_template"]).call
        suggestion = run.suggestions.create!(
          prompt: run.prompt,
          reasoning: result["reasoning"],
          suggested_template: result["suggested_template"],
          original_template: result["original_template"],
          validation_summary: validation,
          status: "ready"
        )
        text_result(
          suggestion_id: suggestion.id,
          prompt_id: run.prompt.id,
          reasoning: suggestion.reasoning,
          suggested_template: suggestion.suggested_template,
          original_template: suggestion.original_template,
          validation: validation,
          net_negative: suggestion.net_negative?
        )
      end
    end
  end
end
