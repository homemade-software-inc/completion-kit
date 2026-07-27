module CompletionKit
  class Dataset < ApplicationRecord
    include CompletionKit::Taggable

    has_many :runs, dependent: :destroy

    validates :name, presence: true
    validates :csv_data, presence: true
    validate :csv_data_within_size_limit

    def csv_data_within_size_limit
      return if csv_data.blank?
      return if csv_data.bytesize <= CompletionKit.config.max_upload_bytes

      errors.add(:csv_data, "is too large (limit #{CompletionKit.config.max_upload_bytes / (1024 * 1024)} MB)")
    end

    def as_json(options = {})
      {
        id: id, name: name, csv_data: csv_data,
        created_at: created_at, updated_at: updated_at,
        tags: tags.as_json
      }
    end

    def row_count
      return 0 if csv_data.blank?

      require "csv"
      @row_count ||= begin
        count = 0
        ::CSV.new(csv_data, headers: true).each { count += 1 }
        count
      rescue ::CSV::MalformedCSVError
        0
      end
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
