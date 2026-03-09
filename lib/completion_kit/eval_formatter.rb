module CompletionKit
  class EvalFormatter
    def self.format_results(results)
      lines = ["\nCompletionKit Evals\n"]

      results.each do |result|
        if result[:error]
          lines << "  #{result[:eval_name]}  ERROR: #{result[:error]}"
          lines << ""
          next
        end

        lines << "  #{result[:eval_name]}  #{result[:row_count]} rows"

        result[:metrics].each do |m|
          status = m[:passed] ? "pass" : "FAIL"
          lines << "    %-20s avg %-6s (threshold %-4s) %s" % [
            m[:key], m[:average], m[:threshold], status
          ]
        end

        lines << ""
      end

      passed = results.count { |r| r[:passed] }
      failed = results.count { |r| !r[:passed] }
      lines << "#{passed} passed, #{failed} failed"

      failures = results.reject { |r| r[:passed] }
      failures.each do |result|
        if result[:error]
          lines << "Failed: #{result[:eval_name]} — #{result[:error]}"
        else
          result[:metrics].reject { |m| m[:passed] }.each do |m|
            lines << "Failed: #{result[:eval_name]} — #{m[:key]} scored #{m[:average]}, threshold #{m[:threshold]}"
          end
        end
      end

      lines.join("\n") + "\n"
    end
  end
end
