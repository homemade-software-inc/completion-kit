module CompletionKit
  module McpTools
    module Datasets
      TOOLS = {
        "datasets_list" => {
          description: "List all datasets",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "datasets_get" => {
          description: "Get a dataset by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "datasets_create" => {
          description: "Create a dataset with CSV data",
          inputSchema: {
            type: "object",
            properties: {name: {type: "string"}, csv_data: {type: "string"}},
            required: ["name", "csv_data"]
          },
          handler: :create
        },
        "datasets_update" => {
          description: "Update a dataset",
          inputSchema: {
            type: "object",
            properties: {id: {type: "integer"}, name: {type: "string"}, csv_data: {type: "string"}},
            required: ["id"]
          },
          handler: :update
        },
        "datasets_delete" => {
          description: "Delete a dataset",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(_args)
        text_result(Dataset.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Dataset.find(args["id"]).as_json)
      end

      def self.create(args)
        dataset = Dataset.new(args.slice("name", "csv_data"))
        if dataset.save
          text_result(dataset.as_json)
        else
          error_result(dataset.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        dataset = Dataset.find(args["id"])
        if dataset.update(args.except("id").slice("name", "csv_data"))
          text_result(dataset.as_json)
        else
          error_result(dataset.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Dataset.find(args["id"]).destroy!
        text_result("Dataset #{args["id"]} deleted")
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end
    end
  end
end
