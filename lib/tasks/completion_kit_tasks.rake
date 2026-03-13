namespace :completion_kit do
  desc "Run all prompt evals in evals/ directory"
  task eval: :environment do
    eval_files = Dir[Rails.root.join("evals/**/*_eval.rb")]

    if eval_files.empty?
      puts "No eval files found in evals/. Create evals/*_eval.rb files."
      exit 0
    end

    CompletionKit.clear_evals!
    eval_files.each { |f| load f }

    if CompletionKit.registered_evals.empty?
      puts "No evals registered. Use CompletionKit.define_eval in your eval files."
      exit 0
    end

    results = CompletionKit.registered_evals.map do |defn|
      errors = defn.validation_errors
      if errors.any?
        { eval_name: defn.eval_name, row_count: 0, metrics: [], passed: false, error: errors.join(", ") }
      else
        runner = CompletionKit::EvalRunner.new(defn)
        runner.run
      end
    end

    puts CompletionKit::EvalFormatter.format_results(results)

    exit 1 if results.any? { |r| !r[:passed] }
  end

  namespace :eval do
    desc "Dry run: validate eval definitions without calling APIs"
    task dry_run: :environment do
      eval_files = Dir[Rails.root.join("evals/**/*_eval.rb")]

      if eval_files.empty?
        puts "No eval files found in evals/."
        exit 0
      end

      CompletionKit.clear_evals!
      eval_files.each { |f| load f }

      puts "\nCompletionKit Eval Dry Run\n\n"

      all_valid = true
      CompletionKit.registered_evals.each do |defn|
        errors = defn.validation_errors

        prompt = begin
          CompletionKit::Prompt.current_for(defn.prompt_name)
        rescue ActiveRecord::RecordNotFound
          nil
        end if defn.prompt_name
        errors << "Prompt '#{defn.prompt_name}' not found" if defn.prompt_name && !prompt
        errors << "Dataset '#{defn.dataset_path}' not found" if defn.dataset_path && !File.exist?(defn.dataset_path)

        defn.metrics.each do |m|
          unless CompletionKit::Metric.exists?(key: m[:key].to_s)
            errors << "Unknown metric key: #{m[:key]}"
          end
        end

        if errors.any?
          all_valid = false
          puts "  #{defn.eval_name}  INVALID"
          errors.each { |e| puts "    - #{e}" }
        else
          row_count = File.readlines(defn.dataset_path).size - 1
          puts "  #{defn.eval_name}  OK (#{row_count} rows, #{defn.metrics.size} metrics)"
        end
        puts ""
      end

      exit 1 unless all_valid
    end
  end

  desc "List available metrics and their keys"
  task metrics: :environment do
    metrics = CompletionKit::Metric.order(:name)

    if metrics.empty?
      puts "No metrics defined yet."
      exit 0
    end

    puts "\nAvailable metrics:\n\n"
    metrics.each do |m|
      puts "  %-25s key: %s" % [m.name, m.key || "(no key)"]
    end
    puts ""
  end
end
