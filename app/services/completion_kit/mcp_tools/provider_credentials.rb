module CompletionKit
  module McpTools
    module ProviderCredentials
      extend Base

      TOOLS = {
        "provider_credentials_list" => {
          description: "List all provider credentials (API keys are not exposed)",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "provider_credentials_get" => {
          description: "Get a provider credential by ID (API key is not exposed)",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "provider_credentials_create" => {
          description: "Create a provider credential",
          inputSchema: {
            type: "object",
            properties: {
              provider: {type: "string", enum: ["openai", "anthropic", "ollama", "openrouter"]},
              api_key: {type: "string"},
              api_endpoint: {type: "string"}
            },
            required: ["provider", "api_key"]
          },
          handler: :create
        },
        "provider_credentials_update" => {
          description: "Update a provider credential",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, provider: {type: "string"},
              api_key: {type: "string"}, api_endpoint: {type: "string"}
            },
            required: ["id"]
          },
          handler: :update
        },
        "provider_credentials_delete" => {
          description: "Delete a provider credential",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.list(_args)
        text_result(ProviderCredential.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(ProviderCredential.find(args["id"]).as_json)
      end

      def self.create(args)
        credential = ProviderCredential.new(args.slice("provider", "api_key", "api_endpoint"))
        if credential.save
          text_result(credential.as_json)
        else
          error_result(credential.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        credential = ProviderCredential.find(args["id"])
        if credential.update(args.except("id").slice("provider", "api_key", "api_endpoint"))
          text_result(credential.as_json)
        else
          error_result(credential.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        ProviderCredential.find(args["id"]).destroy!
        text_result("Provider credential #{args["id"]} deleted")
      end
    end
  end
end
