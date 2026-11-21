module CompletionKit
  module McpTools
    module Tags
      extend Base

      TOOLS = {
        "tags_list" => {
          description: "List every tag in CompletionKit, in name order. Returns each tag's id, name, color and timestamps. Tags label prompts, datasets, metrics, metric groups and runs. Use this to see which labels exist, or to find a tag's ID before renaming or deleting it.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "tags_get" => {
          description: "Get one tag by ID. Returns its id, name, color and timestamps. Use it to check a tag's current name before you rename it or pass it in tag_names.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "tags_create" => {
          description: "Create a tag for labelling prompts, datasets, metrics, metric groups and runs. The name is trimmed and lowercased. It may contain only the letters a to z, digits, spaces, hyphens and underscores (accented and non-Latin letters are rejected), can be up to 64 characters, and must not match an existing tag. Color is auto-assigned. Returns the new tag. You don't need this tool before tagging a record, because the create and update tools for those records take tag_names and create missing tags for you.",
          annotations: Base::ADDITIVE,
          inputSchema: {
            type: "object",
            properties: {name: {type: "string"}},
            required: ["name"]
          },
          handler: :create
        },
        "tags_update" => {
          description: "Rename a tag. Pass the new name; leaving it out returns an error. The name follows the same rules as tags_create and can't match another tag, because tags are not merged. The new name shows at once on every prompt, dataset, metric, metric group and run that carries the tag. Returns the updated tag.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {
            type: "object",
            properties: {id: {type: "integer"}, name: {type: "string"}},
            required: ["id"]
          },
          handler: :update
        },
        "tags_delete" => {
          description: "Delete a tag. Removes the tag from every linked metric, metric group, prompt, run, and dataset; those records themselves are kept. This cannot be undone. Use tags_update instead if you only want to rename it. Returns a confirmation message.",
          annotations: Base::DESTRUCTIVE,
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
