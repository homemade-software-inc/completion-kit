module CompletionKit
  class EvalDefinition
    attr_reader :eval_name, :prompt_name, :dataset_path, :metrics

    def initialize(name)
      @eval_name = name
      @prompt_name = nil
      @dataset_path = nil
      @judge_model_name = nil
      @metrics = []
    end

    def prompt(name)
      @prompt_name = name
    end

    def dataset(path)
      @dataset_path = path
    end

    def judge_model(model)
      @judge_model_name = model
    end

    def judge_model_name
      @judge_model_name || CompletionKit.config.judge_model
    end

    def metric(key, threshold:)
      @metrics << { key: key, threshold: threshold }
    end

    def validation_errors
      errors = []
      errors << "No prompt specified" unless @prompt_name
      errors << "No dataset specified" unless @dataset_path
      errors << "No metrics specified" if @metrics.empty?
      errors
    end

    def valid?
      validation_errors.empty?
    end
  end
end
