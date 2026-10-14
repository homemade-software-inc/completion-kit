require "csv"

module CsvReadsHelper
  def track_csv_reads
    sizes = []
    allow(CSV).to receive(:new).and_wrap_original do |original, data, **options|
      sizes << data.bytesize
      original.call(data, **options)
    end
    sizes
  end
end

RSpec.configure do |config|
  config.include CsvReadsHelper
end
