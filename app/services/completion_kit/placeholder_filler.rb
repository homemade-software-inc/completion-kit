module CompletionKit
  class PlaceholderFiller
    WHITESPACE = [9, 10, 11, 12, 13, 32].freeze

    def self.fill(template, values)
      new(template, values).fill
    end

    def initialize(template, values)
      @template = template
      @values = values
      @ranks = values.keys.each_with_index.to_h
      @padded = {}
      @braced = []
      @blank_lengths = []
      values.each_key { |name| classify(name) }
      @padded.each_value { |cores| cores.each_value(&:sort!) }
    end

    def fill
      rendered = String.new(encoding: @template.encoding)
      copied = cursor = 0
      while (opener = @template.byteindex("{{", cursor)) && closer_from(opener + 2)
        name, stop = placeholder_at(opener + 2)
        if name
          rendered << @template.byteslice(copied, opener - copied) << @values[name].to_s
          copied = cursor = stop
        else
          cursor = opener + 1
        end
      end
      rendered << @template.byteslice(copied, @template.bytesize - copied)
    end

    private

    def classify(name)
      lead = whitespace_after(name, 0)
      if name.include?("}}") || name.end_with?("}")
        @braced << [name, lead]
      elsif lead == name.bytesize
        @blank_lengths |= [lead]
      else
        trail = whitespace_before(name, name.bytesize)
        add(@padded, name.byteslice(lead, name.bytesize - lead - trail), [lead, @ranks[name], trail, name])
      end
    end

    def add(table, key, entry)
      ((table[key.bytesize] ||= {})[key] ||= []) << entry
    end

    def closer_from(start)
      unless @closer && @closer >= start
        @closer = @template.byteindex("}}", start)
        @tail = nil
      end
      @closer
    end

    def placeholder_at(start)
      top = start + whitespace_after(@template, start)
      best([plain_match(start, top), braced_match(start, top)].compact)&.drop(1)
    end

    def plain_match(start, top)
      found = top == @closer ? blank_match(start) : padded_match(start, top)
      found && [*found, @closer + 2]
    end

    def blank_match(start)
      return if @blank_lengths.empty?

      @closer.downto(start) do |from|
        names = @blank_lengths.filter_map { |length| @template.byteslice(from, length) if from + length <= @closer }
        name = first_ranked(names)
        return [from, name] if name
      end
      nil
    end

    def padded_match(start, top)
      @tail ||= @closer - whitespace_before(@template, @closer)
      entry = entries_at(@padded, top, @tail)&.find do |lead, _, trail, name|
        lead <= top - start && trail <= @closer - @tail && @template.byteslice(top - lead, name.bytesize) == name
      end
      [top - entry.first, entry.last] if entry
    end

    def braced_match(start, top)
      best(@braced.filter_map do |name, lead|
        from = top - lead
        next if from < start || @template.byteslice(from, name.bytesize) != name

        finish = from + name.bytesize
        finish += whitespace_after(@template, finish)
        [from, name, finish + 2] if @template.byteslice(finish, 2) == "}}"
      end)
    end

    def entries_at(table, from, stop)
      keys = table[stop - from]
      keys[@template.byteslice(from, stop - from)] if keys
    end

    def best(matches)
      matches.max_by { |from, name, _| [from, -@ranks[name]] }
    end

    def first_ranked(names)
      names.select { |name| @ranks.key?(name) }.min_by { |name| @ranks[name] }
    end

    def whitespace_after(text, from)
      count = 0
      count += 1 while WHITESPACE.include?(text.getbyte(from + count))
      count
    end

    def whitespace_before(text, stop)
      count = 0
      count += 1 while count < stop && WHITESPACE.include?(text.getbyte(stop - count - 1))
      count
    end
  end
end
