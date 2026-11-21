require "faraday"

module CompletionKit
  module McpTools
    module Datasets
      extend Base

      MAX_CSV_BYTES = 10 * 1024 * 1024

      TOOLS = {
        "datasets_list" => {
          description: "List every test dataset in your CompletionKit account, newest first. Returns each dataset's id, name, full CSV data, tags and timestamps, so the result can be large when your datasets are big. Use it to find a dataset to test a prompt against or to score AI responses on. To read one dataset, use datasets_get.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "datasets_get" => {
          description: "Get one test dataset by its ID. Returns the dataset's name, its full CSV data (header row first, then one test case per row), its tags and its timestamps. Use it to check a dataset's columns and rows before you test a prompt or start a run against it.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "datasets_create" => {
          description: "Create a test dataset from CSV text included in the call. The first row is the header, and each later row is one test case. Every column is available to the prompt as a variable. Two column names are recognized specially: \"expected_output\" is each row's answer key (ground truth) given to the judge and to checks that compare against the row's expected value, and \"actual_output\" is a pre-made output to score in a prompt-less run. Both are overridable per run (expected_column / output_column). Optional tag_names labels the dataset. Tag names are lowercased and may contain only unaccented letters, numbers, spaces, hyphens and underscores, up to 64 characters, and tags that don't exist yet are created. Returns the new dataset. The CSV is rejected if it is empty, is not valid UTF-8, has a blank header row or a header row over 64 KB, or is larger than the upload limit (25 MB by default). If the CSV is too big to put in the call, use datasets_create_from_url, which downloads files up to 10MB.",
          annotations: Base::ADDITIVE,
          inputSchema: {
            type: "object",
            properties: {name: {type: "string"}, csv_data: {type: "string"}, tag_names: {type: "array", items: {type: "string"}}},
            required: ["name", "csv_data"]
          },
          handler: :create
        },
        "datasets_update" => {
          description: "Change a test dataset's name, CSV data or tags. Passing csv_data replaces the whole CSV, and the dataset keeps no copy of the old version. Passing tag_names replaces all of the dataset's tags. Responses from runs that already ran keep the row values they used, but any run started after the change reads the new rows. If you remove or rename a column that a run needs (a variable in its prompt, its expected_column or its output column), that run cannot be started, finished, regraded, retried or rerun until the column is back. To add rows, read the dataset with datasets_get first and send back the full CSV. Returns the updated dataset. If tag_names is rejected, the name and CSV changes in the same call are still saved.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {
            type: "object",
            properties: {id: {type: "integer"}, name: {type: "string"}, csv_data: {type: "string"}, tag_names: {type: "array", items: {type: "string"}}},
            required: ["id"]
          },
          handler: :update
        },
        "datasets_delete" => {
          description: "Permanently delete a test dataset. This also deletes every run that used it, with those runs' responses, scores, suggestions and human agreement labels. Prompts and metrics are kept. This cannot be undone, so confirm with the user before calling it. Returns a short confirmation.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "datasets_create_from_url" => {
          description: "Create a test dataset by downloading a CSV file from a public http(s) URL instead of pasting it into the call. Use this for large datasets: the server fetches the CSV directly, so the data never has to pass through the tool-call arguments. The URL is SSRF-checked, so it cannot point at private network addresses. Redirects are not followed and return an error, and files over 10MB are rejected. The first row is the header. The \"expected_output\" (answer key) and \"actual_output\" (pre-made output) columns are recognized specially, and both are overridable per run. Optional tag_names labels the dataset. Returns the new dataset, or an error that says why the URL, the download or the CSV was rejected.",
          annotations: Base::OPEN_WORLD_ADDITIVE,
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
        response = csv_connection(args["url"]).get(args["url"])
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
      rescue ProviderEndpoint::UnsafeEndpoint => e
        error_result("URL is not allowed: it #{e.message}.")
      rescue Faraday::Error => e
        error_result("Could not download CSV. #{EndpointError.from(e).message}")
      end

      def self.csv_connection(url)
        Faraday.new do |f|
          f.options.timeout = 30
          f.options.open_timeout = 5
          ProviderEndpoint.pin(f, url)
        end
      end
    end
  end
end
