module CompletionKit
  module McpTools
    module Responses
      extend Base

      FIELDS_DESCRIPTION = "Only return these keys, keeping the payload small. Response keys: id, run_id, " \
                           "input_data, response_text, expected_output, created_at, score, reviewed, reviews, " \
                           "status, attempts, row_index, error. Prefix with \"reviews.\" to trim each review, " \
                           "e.g. [\"score\", \"reviews.metric_name\", \"reviews.ai_score\"]. id is always included.".freeze

      TOOLS = {
        "responses_list" => {
          description: "List responses for a run, in row order. Returns " \
                       "{total, limit, offset, returned, responses}. Defaults to #{Base::DEFAULT_PAGE_LIMIT} rows " \
                       "because full payloads are large: use \"fields\" to drop the bodies, \"min_score\"/\"max_score\" " \
                       "to isolate low scorers, and sort \"score_asc\" to read the worst rows first. For per-metric " \
                       "averages of the whole run use runs_get instead of aggregating here.",
          inputSchema: {
            type: "object",
            properties: {
              run_id: {type: "integer"},
              limit: {type: "integer", description: "Rows to return; defaults to #{Base::DEFAULT_PAGE_LIMIT}, capped at #{Base::MAX_PAGE_LIMIT}."},
              offset: {type: "integer", description: "Rows to skip before returning results."},
              status: {type: "string", description: "Filter by row status: pending, retrying, succeeded or failed."},
              min_score: {type: "number", description: "Only rows whose average judge score is at least this."},
              max_score: {type: "number", description: "Only rows whose average judge score is at most this. Use with sort \"score_asc\" for failure-mode analysis."},
              sort: {type: "string", enum: ResponseQuery::SORTS, description: "Row order; defaults to \"id\"."},
              fields: {type: "array", items: {type: "string"}, description: FIELDS_DESCRIPTION}
            },
            required: ["run_id"]
          },
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
        query = ResponseQuery.new(
          run,
          status: args["status"], min_score: args["min_score"], max_score: args["max_score"],
          sort: args["sort"], fields: args["fields"]
        )
        scope = query.relation
        total = scope.count
        limit, offset = page_bounds(args)
        rows = scope.limit(limit).offset(offset).to_a

        text_result({
          total: total, limit: limit, offset: offset, returned: rows.length,
          responses: rows.map { |response| query.serialize(response) }
        })
      end

      def self.get(args)
        run = Run.find(args["run_id"])
        text_result(run.responses.find(args["id"]).as_json)
      end
    end
  end
end
