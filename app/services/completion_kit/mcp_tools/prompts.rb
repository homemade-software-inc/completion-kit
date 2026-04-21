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
              template: {type: "string"}, llm_model: {type: "string"}
            },
            required: ["name", "template", "llm_model"]
          },
          handler: :create
        },
        "prompts_update" => {
          description: "Update a prompt",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, description: {type: "string"},
              template: {type: "string"}, llm_model: {type: "string"}
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
      }.freeze

      def self.list(_args)
        text_result(Prompt.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Prompt.find(args["id"]).as_json)
      end

      def self.create(args)
        prompt = Prompt.new(args.slice("name", "description", "template", "llm_model"))
        if prompt.save
          text_result(prompt.as_json)
        else
          error_result(prompt.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        prompt = Prompt.find(args["id"])
        attrs = args.except("id").slice("name", "description", "template", "llm_model")
        if prompt.runs.exists?
          new_prompt = prompt.clone_as_new_version(attrs)
          new_prompt.publish!
          text_result(new_prompt.as_json)
        elsif prompt.update(attrs)
          text_result(prompt.as_json)
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
    end
  end
end
