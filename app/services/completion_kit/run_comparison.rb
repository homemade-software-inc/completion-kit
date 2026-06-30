module CompletionKit
  module RunComparison
    module_function

    def result_change(left_passed, right_passed)
      return nil if left_passed.nil? || right_passed.nil?
      return "broke" if left_passed && !right_passed
      return "fixed" if !left_passed && right_passed

      "same"
    end
  end
end
