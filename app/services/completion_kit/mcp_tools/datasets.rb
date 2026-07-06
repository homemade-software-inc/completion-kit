require "faraday"

module CompletionKit
  module McpTools
    module Datasets
      extend Base

      MAX_CSV_BYTES = 10 * 1024 * 1024

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
          description: "Create a dataset with CSV data. First row is the header. Two column names are recognized specially: \"expected_output\" is each row's answer key (ground truth) given to the judge and to checks that compare against the row's expected value, and \"actual_output\" is a pre-made output to score in a prompt-less run. Both are overridable per run (expected_column / output_column). Every column is also available to the prompt as a variable.",
          inputSchema: {
            type: "object",
            properties: {name: {type: "string"}, csv_data: {type: "string"}, tag_names: {type: "array", items: {type: "string"}}},
            required: ["name", "csv_data"]
          },
          handler: :create
        },
        "datasets_update" => {
          description: "Update a dataset",
          inputSchema: {
            type: "object",
            properties: {id: {type: "integer"}, name: {type: "string"}, csv_data: {type: "string"}, tag_names: {type: "array", items: {type: "string"}}},
            required: ["id"]
          },
          handler: :update
        },
        "datasets_delete" => {
          description: "Delete a dataset",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "datasets_create_from_url" => {
          description: "Create a dataset by downloading CSV from a URL instead of inlining it. Use this for large datasets: pass a public http(s) URL and the server fetches the CSV directly, so the data never has to pass through the tool-call arguments. The URL is SSRF-checked and the download is capped at 10MB. First row is the header; the \"expected_output\" (answer key) and \"actual_output\" (pre-made output) columns are recognized specially, overridable per run.",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"},
              url: {type: "string", description: "Public http(s) URL of the CSV file to download."},
              tag_names: {type: "array", items: {type: "string"}}
            },
            required: ["name", "url"]
          },
          handler: :create_from_url
        }
      }.freeze

      def self.list(_args)
        text_result(Dataset.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Dataset.find(args["id"]).as_json)
      end

      def self.create(args)
        dataset = Dataset.new(args.slice("name", "csv_data"))
        dataset.tag_names = args["tag_names"] if args.key?("tag_names")
        if dataset.save
          text_result(dataset.reload.as_json)
        else
          error_result(dataset.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        dataset = Dataset.find(args["id"])
        if dataset.update(args.except("id").slice("name", "csv_data"))
          dataset.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
          text_result(dataset.reload.as_json)
        else
          error_result(dataset.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Dataset.find(args["id"]).destroy!
        text_result("Dataset #{args["id"]} deleted")
      end

      def self.create_from_url(args)
        issues = ProviderEndpoint.validate(args["url"])
        return error_result("URL is not allowed (#{issues.join(", ")}).") if issues.any?

        response = csv_connection.get(args["url"])
        return error_result("Could not download CSV (HTTP #{response.status}).") unless response.success?

        body = response.body.to_s
        return error_result("CSV is larger than the #{MAX_CSV_BYTES / (1024 * 1024)}MB limit.") if body.bytesize > MAX_CSV_BYTES

        dataset = Dataset.new(name: args["name"], csv_data: body.dup.force_encoding("UTF-8"))
        dataset.tag_names = args["tag_names"] if args.key?("tag_names")
        if dataset.save
          text_result(dataset.reload.as_json)
        else
          error_result(dataset.errors.full_messages.join(", "))
        end
      rescue Faraday::Error => e
        error_result("Could not download CSV: #{e.message}")
      end

      def self.csv_connection
        Faraday.new do |f|
          f.options.timeout = 30
          f.options.open_timeout = 5
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
