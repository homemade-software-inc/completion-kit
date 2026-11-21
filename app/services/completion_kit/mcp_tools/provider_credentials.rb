module CompletionKit
  module McpTools
    module ProviderCredentials
      extend Base

      TOOLS = {
        "provider_credentials_list" => {
          description: "List the model provider connections saved in your CompletionKit account (OpenAI, Anthropic, Ollama or another OpenAI-compatible endpoint, OpenRouter, Azure AI Foundry). Returns each one's id, provider, custom endpoint, API version and timestamps. API keys are not exposed. Use it to see which providers are connected before you test a prompt, start a run or use an LLM judge. It does not show whether a key is still stored or whether the provider's models loaded.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "provider_credentials_get" => {
          description: "Get one saved model provider connection by its ID. Returns its provider, custom endpoint, API version and timestamps. The API key is not exposed. Use it to check how a provider is set up before you change it.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "provider_credentials_create" => {
          description: "Save an API key for a model provider (openai, anthropic, ollama for Ollama or any other OpenAI-compatible endpoint, openrouter or azure_foundry) so CompletionKit can run your prompts and LLM judges with it. You can save one credential per provider. azure_foundry requires api_endpoint, ollama needs api_endpoint for its models to load, and any api_endpoint must be an http(s) URL that resolves to a public address. The key is stored encrypted and is never returned. Saving starts a background job that lists the provider's models. For every provider except openrouter, the job then sends each model that has not been tested yet a short test prompt to check it can generate text and, if it can, a second one to check it can judge, and these requests use your key. Returns the saved credential without the key.",
          annotations: Base::OPEN_WORLD_ADDITIVE,
          inputSchema: {
            type: "object",
            properties: {
              provider: {type: "string", enum: ["openai", "anthropic", "ollama", "openrouter", "azure_foundry"]},
              api_key: {type: "string"},
              api_endpoint: {type: "string"},
              api_version: {type: "string"}
            },
            required: ["provider", "api_key"]
          },
          handler: :create
        },
        "provider_credentials_update" => {
          description: "Change a saved model provider connection: its API key, provider, custom endpoint or API version. A new api_key replaces the stored key, and the old key cannot be recovered. An empty api_key clears the stored key. Changing provider or api_endpoint on a credential with a stored key requires api_key in the same call, so a stored key never moves to a new provider or endpoint. Each provider can have only one credential. Any api_endpoint must be an http(s) URL that resolves to a public address. Each successful save runs model discovery again in the background. It lists the provider's models and, for every provider except openrouter, sends each model that has not been tested yet a short test prompt to check it can generate text and, if it can, a second one to check it can judge, using the key. Models the provider no longer lists are marked retired, and prompts or judges set to a retired model can fail to run. Returns the credential without the key.",
          annotations: Base::OPEN_WORLD_DESTRUCTIVE,
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, provider: {type: "string"},
              api_key: {type: "string", description: "Required when provider or api_endpoint changes and a key is stored"},
              api_endpoint: {type: "string"}, api_version: {type: "string"}
            },
            required: ["id"]
          },
          handler: :update
        },
        "provider_credentials_delete" => {
          description: "Permanently delete a saved model provider connection and its stored API key, and remove that provider's models from your model list. It is refused with an error while any current prompt version uses one of that provider's models, or while any run, including past runs, used one of them as its judge. This cannot be undone, so confirm with the user before calling it. Returns a short confirmation.",
          annotations: Base::DESTRUCTIVE,
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
        credential = ProviderCredential.new(args.slice("provider", "api_key", "api_endpoint", "api_version"))
        if credential.save
          text_result(credential.as_json)
        else
          error_result(credential.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        credential = ProviderCredential.find(args["id"])
        if credential.update(args.except("id").slice("provider", "api_key", "api_endpoint", "api_version"))
          text_result(credential.as_json)
        else
          error_result(credential.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        credential = ProviderCredential.find(args["id"])
        if credential.destroy
          text_result("Provider credential #{args["id"]} deleted")
        else
          error_result(credential.errors.full_messages.join(", "))
        end
      end
    end
  end
end
