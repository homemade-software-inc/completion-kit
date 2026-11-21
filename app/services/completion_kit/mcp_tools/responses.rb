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
          description: "List the AI responses in a run with their scores, in row order, to see which test cases scored well or badly and why. Each row has the input, the response_text, the expected_output, an average judge score from 1 to 5 (5 is best), and each metric's review with judge feedback or a check's pass/fail. Returns {total, limit, offset, returned, responses}. Defaults to #{Base::DEFAULT_PAGE_LIMIT} rows because full payloads are large: use \"fields\" to drop the bodies, \"min_score\"/\"max_score\" to isolate low scorers, and sort \"score_asc\" to read the worst rows first. Rows with no judge score, such as rows graded only by checks, are left out by a score filter and listed last by a score sort. For per-metric averages of the whole run use runs_get instead of aggregating here.",
          annotations: Base::READ_ONLY,
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
          description: "Get one response from a run in full, by run_id and response id. The response must belong to that run. Returns the input, the complete response_text, the expected_output, the average judge score from 1 to 5 (5 is best), each metric's review with the judge's score and feedback or the check's pass/fail, the row's status and attempts, and any provider error. Use it to read a single test case closely after responses_list points you to it.",
          annotations: Base::READ_ONLY,
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
