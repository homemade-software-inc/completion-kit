module CompletionKit
  module McpTools
    module Responses
      extend Base

      TOOLS = {
        "responses_list" => {
          description: "List responses for a run",
          inputSchema: {type: "object", properties: {run_id: {type: "integer"}}, required: ["run_id"]},
          handler: :list
        },
        "responses_get" => {
          description: "Get a specific response",
          inputSchema: {
            type: "object",
            properties: {run_id: {type: "integer"}, id: {type: "integer"}},
            required: ["run_id", "id"]
          },
          handler: :get
        }
      }.freeze

      def self.list(args)
        run = Run.find(args["run_id"])
        text_result(run.responses.includes(:reviews).map(&:as_json))
      end

      def self.get(args)
        run = Run.find(args["run_id"])
        text_result(run.responses.find(args["id"]).as_json)
      end
    end
  end
end
