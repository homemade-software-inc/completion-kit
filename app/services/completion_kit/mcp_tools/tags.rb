module CompletionKit
  module McpTools
    module Tags
      extend Base

      TOOLS = {
        "tags_list" => {
          description: "List all tags",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "tags_get" => {
          description: "Get a tag by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "tags_create" => {
          description: "Create a tag. Color is auto-assigned.",
          inputSchema: {
            type: "object",
            properties: {name: {type: "string"}},
            required: ["name"]
          },
          handler: :create
        },
        "tags_update" => {
          description: "Rename a tag.",
          inputSchema: {
            type: "object",
            properties: {id: {type: "integer"}, name: {type: "string"}},
            required: ["id"]
          },
          handler: :update
        },
        "tags_delete" => {
          description: "Delete a tag. Removes the tag from every linked metric, prompt, run, and dataset.",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.list(_args)
        text_result(CompletionKit::Tag.order(:name).map(&:as_json))
      end

      def self.get(args)
        text_result(CompletionKit::Tag.find(args["id"]).as_json)
      end

      def self.create(args)
        tag = CompletionKit::Tag.new(name: args["name"])
        if tag.save
          text_result(tag.as_json)
        else
          error_result(tag.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        tag = CompletionKit::Tag.find(args["id"])
        if tag.update(name: args["name"])
          text_result(tag.as_json)
        else
          error_result(tag.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        CompletionKit::Tag.find(args["id"]).destroy!
        text_result("Tag #{args["id"]} deleted")
      end
    end
  end
end
