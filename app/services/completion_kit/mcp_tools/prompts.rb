module CompletionKit
  module McpTools
    module Prompts
      extend Base

      TOOLS = {
        "prompts_list" => {
          description: "List every prompt in CompletionKit, newest first. Each version of a prompt is its own entry, so drafts and older versions appear next to the published one. Versions of the same prompt share a family_key, and current=true marks the published version that apps get when they fetch the prompt by name or family_key. Returns each version's id, name, description, template, llm_model, family_key, version_number, current, timestamps and tags. Use it to find a prompt's ID before you test it, edit it, compare its versions or ask for a suggested improvement.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "prompts_get" => {
          description: "Get one prompt version by its numeric ID. Returns its name, description, template text with {{variable}} placeholders, the model that answers it (llm_model), family_key, version_number, whether it is the published version (current), timestamps and tags. Use it to read a prompt before you edit it, test it in a run or compare it with another version.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {id: {type: "integer", description: "Prompt ID"}}, required: ["id"]},
          handler: :get
        },
        "prompts_create" => {
          description: "Create a new prompt to test. Give it a name, a template with {{variable}} placeholders that match your dataset's column names, and the model that should answer it (llm_model). The model name is checked against the models your saved provider keys serve. If CompletionKit has not found any models from a saved key yet, any model name is accepted, and runs fail until a key for that model's provider is added. The new prompt is version 1 of a new prompt family and is published right away. If another published prompt already has the same name, apps that fetch prompts by name get this new one instead. To change an existing prompt, use prompts_update so its versions stay together. tag_names creates any tags that don't exist yet. Returns the saved prompt with its ID. To test it, create a run with runs_create and start it with runs_generate.",
          annotations: Base::DESTRUCTIVE,
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
          description: "Edit a prompt's name, description, template, model or tags. Changing the template or model of the published version, or editing any version that already has runs, creates a new DRAFT version (current=false) instead of changing it, so an agent's edits don't go live without a gate. The draft copies the old version's name, description, template and model, with your changes applied. Run and compare the draft, then promote it with prompts_publish. An unpublished draft with no runs, or a name, description or tag change on a published version with no runs, is updated in place and the old values are not kept. Renaming a published version in place takes effect at once, so apps that fetch it by its old name stop finding it, while fetches by family_key or ID still work. tag_names replaces the whole tag list. A new draft does not copy the old version's tags, so pass tag_names to keep them, or the draft has no tags, even after it is published. Returns the saved version, which has a new ID when a draft was created.",
          annotations: Base::DESTRUCTIVE,
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
          description: "Permanently delete one prompt version by ID, along with every run of that version and all of those runs' responses, scores, judge reviews, agreements and suggestions. Other versions of the prompt, and your datasets, metrics and tags, are kept. Apps that fetch this version by its ID get a not-found error. If you delete the published version, no other version is published in its place, so apps that fetch the prompt by family_key get a not-found error, and apps that fetch it by name get a not-found error or another published prompt with the same name, until you publish another version with prompts_publish. This cannot be undone. Returns a confirmation message.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "prompts_publish" => {
          description: "Publish a prompt version, making it the current version. Apps that fetch the prompt by its name or family_key get this version from their next request, and the version that was published before stops being current. Use it to ship a draft from prompts_update once a run shows it scores at least as well, or to roll back by publishing an older version. Returns the published version.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :publish
        },
        "prompts_suggest_improvement" => {
          description: "Suggest an improved version of a prompt, grounded in a run's test results and judge feedback. It reads up to 20 of the run's responses with their scores and reviews, then asks the prompt's own model, on your saved provider key, for reasoning plus a rewritten template that keeps the {{variables}}. It then tests the rewrite on up to 30 of the run's judge-scored rows and scores the new answers with the run's LLM-judge metrics and judge model. Returns suggestion_id, prompt_id, reasoning, suggested_template, original_template, validation (before and after averages and how many rows improved, regressed or stayed the same) and net_negative, which is true when the rewrite's average score fell or more rows got worse than better. If validation.tested is 0, nothing was checked and net_negative is false. That happens when the run has no LLM-judge metrics, has no judge-scored rows with both input and output, or every test call failed. It saves the result as a Suggestion. The prompt itself is not changed, so pass suggested_template to prompts_update to save it as a draft version. Requires a run that has a prompt (not a scoring-only run). Each call can make dozens of model calls on your saved provider keys and can take a while.",
          annotations: Base::ADDITIVE,
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
        if prompt.runs.exists? || (prompt.current? && prompt.behavioral_change?(attrs))
          new_prompt = prompt.build_next_version(attrs)
          return error_result(new_prompt.errors.full_messages.join(", ")) unless new_prompt.save

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
        return error_result("A run that only scores existing outputs has no prompt to improve.") if run.prompt.nil?

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
