require "csv"

module CsvReadsHelper
  WHOLE_STRING_SCANS = %i[blank? present? presence lines each_line split scan match match? =~ gsub sub index].freeze

  def track_csv_reads
    sizes = []
    allow(CSV).to receive(:new).and_wrap_original do |original, data, **options|
      sizes << data.bytesize
      original.call(data, **options)
    end
    sizes
  end

  def track_string_scans(string)
    scans = []
    WHOLE_STRING_SCANS.each do |name|
      allow(string).to receive(name).and_wrap_original do |original, *args, &block|
        scans << name
        original.call(*args, &block)
      end
    end
    scans
  end

  def whitespace_led_csv(bytesize)
    tail = "content,expected\nx,y\n"
    ("\n" * (bytesize - tail.bytesize)) + tail
  end
end

RSpec.configure do |config|
  config.include CsvReadsHelper
end
