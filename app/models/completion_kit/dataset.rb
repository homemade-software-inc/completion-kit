module CompletionKit
  class Dataset < ApplicationRecord
    include CompletionKit::Taggable

    HEADER_ROW_LIMIT = 64 * 1024

    has_many :runs, dependent: :destroy

    validates :name, presence: true
    validates :csv_data, presence: true
    validate :csv_data_within_size_limit
    validate :header_row_within_limit, if: :will_save_change_to_csv_data?

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
      row = header_row
      return [] if row.nil?

      require "csv"
      ::CSV.parse(row).first.to_a.map(&:to_s).map(&:strip)
    rescue ::CSV::MalformedCSVError
      []
    end

    def any_rows?
      stop = csv_data.present? && header_row_end
      return false unless stop

      stop += 1 if csv_data.byteslice(stop, 2) == "\r\n"
      csv_data.bytesize > stop + 1
    end

    private

    def header_row
      return if csv_data.blank?

      stop = header_row_end
      return csv_data.byteslice(0, stop) if stop

      csv_data if csv_data.bytesize <= HEADER_ROW_LIMIT
    end

    def header_row_end
      head = csv_data.byteslice(0, HEADER_ROW_LIMIT + 1)
      [head.byteindex("\n"), head.byteindex("\r")].compact.min
    end

    def header_row_within_limit
      return if csv_data.blank? || header_row

      errors.add(:csv_data, "has a header row longer than #{HEADER_ROW_LIMIT / 1024} KB")
    end
  end
end
