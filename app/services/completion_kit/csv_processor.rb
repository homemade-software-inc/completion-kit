module CompletionKit
  class CsvProcessor
    require 'csv'

    def self.process(run)
      return [] if run.csv_data.blank?

      begin
        csv_data = CSV.parse(run.csv_data, headers: true)
        rows = csv_data.map(&:to_h)

        if rows.empty?
          run.errors.add(:csv_data, "No data rows found in CSV")
          return []
        end

        return [] unless validate_variables(run, rows.first.keys)

        rows
      rescue CSV::MalformedCSVError => e
        run.errors.add(:csv_data, "Invalid CSV format: #{e.message}")
        []
      end
    end

    def self.process_self(run)
      return [] unless run.dataset&.csv_data.present?

      begin
        csv_data = CSV.parse(run.dataset.csv_data, headers: true)
        csv_data.map(&:to_h)
      rescue CSV::MalformedCSVError
        []
      end
    end

    def self.extract_variables(prompt)
      return [] if prompt.nil? || prompt.template.blank?

      template = prompt.template
      names = []
      cursor = 0
      while (opener = template.byteindex("{{", cursor)) && (closer = template.byteindex("}", opener + 2))
        if closer > opener + 2 && template.byteslice(closer + 1, 1) == "}"
          names << template.byteslice(opener + 2, closer - opener - 2)
          cursor = closer + 2
        else
          cursor = closer + 1
        end
      end
      names.map(&:strip).uniq
    end

    def self.validate_variables(run, headers)
      prompt_variables = extract_variables(run.prompt)
      missing_variables = prompt_variables - headers

      if missing_variables.any?
        run.errors.add(:csv_data, "Missing required variables in CSV: #{missing_variables.join(', ')}")
        return false
      end

      true
    end

    def self.apply_variables(prompt, variables)
      PlaceholderFiller.fill(prompt.template, variables.to_h.transform_keys(&:to_s))
    end
  end
end
