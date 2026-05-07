module CompletionKit
  class Dataset < ApplicationRecord
    has_many :runs, dependent: :restrict_with_error

    validates :name, presence: true
    validates :csv_data, presence: true

    def as_json(options = {})
      {
        id: id, name: name, csv_data: csv_data,
        created_at: created_at, updated_at: updated_at
      }
    end

    def row_count
      return 0 if csv_data.blank?

      require "csv"
      ::CSV.parse(csv_data, headers: true).length
    rescue ::CSV::MalformedCSVError
      0
    end

    def headers
      return [] if csv_data.blank?

      require "csv"
      ::CSV.parse(csv_data.lines.first.to_s).first.to_a.map(&:to_s).map(&:strip)
    rescue ::CSV::MalformedCSVError
      []
    end
  end
end
