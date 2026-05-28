module CompletionKit
  module StarterMetrics
    Starter = Struct.new(:key, :name, :description, :catches, :instruction, :rubric_bands, keyword_init: true)

    ALL = [
      Starter.new(
        key: "correctness",
        name: "Correctness",
        description: "Is the output factually right and free of made-up information?",
        catches: "Hallucinations, wrong facts, subtle distortions. The most universally-asked question about an LLM's output.",
        instruction: "Is the output factually right and free of made-up information? Penalise hallucinations and subtle factual distortions; reward outputs whose every claim checks out.",
        rubric_bands: [
          { "stars" => 5, "description" => "Every fact in the output checks out." },
          { "stars" => 4, "description" => "Right in substance; minor imprecision or omission." },
          { "stars" => 3, "description" => "Mostly right, one or two facts are off." },
          { "stars" => 2, "description" => "Mostly wrong with a few right details." },
          { "stars" => 1, "description" => "Wrong, misleading, or contains fabricated facts." }
        ]
      ),
      Starter.new(
        key: "instruction_following",
        name: "Instruction following",
        description: "Did the model do everything that was asked?",
        catches: "The response is factually right but ignores \"answer in two sentences\", \"use bullet points\", \"do not include X\". Distinct from Correctness; a response can be right and still fail this.",
        instruction: "Did the model do every concrete thing the prompt asked for? Score against the explicit requirements in the prompt (format constraints, count limits, exclusions, audience cues). Factual accuracy is a different dimension; score that elsewhere.",
        rubric_bands: [
          { "stars" => 5, "description" => "Followed every requirement in the prompt exactly." },
          { "stars" => 4, "description" => "Followed every requirement with a small slip." },
          { "stars" => 3, "description" => "Did the main thing, missed at least one explicit requirement." },
          { "stars" => 2, "description" => "Did some of what was asked, missed the main requirement." },
          { "stars" => 1, "description" => "Ignored the instructions or did something different." }
        ]
      ),
      Starter.new(
        key: "format_compliance",
        name: "Format compliance",
        description: "Does the output follow the required structure?",
        catches: "Invalid JSON, missing schema fields, extra prose around a structured response, wrong casing on keys. Critical for any LLM wired into an API.",
        instruction: "Does the output match the format the prompt asked for: JSON shape, schema, keys, casing, no stray prose? Score on whether a downstream parser would accept it without massaging.",
        rubric_bands: [
          { "stars" => 5, "description" => "Exact spec, ready to consume programmatically." },
          { "stars" => 4, "description" => "Spec-compliant with one cosmetic issue." },
          { "stars" => 3, "description" => "Right shape, minor deviations (extra commentary, casing, ordering)." },
          { "stars" => 2, "description" => "Right format with substantive deviations (missing required fields, wrong types)." },
          { "stars" => 1, "description" => "Wrong format or unparseable." }
        ]
      ),
      Starter.new(
        key: "tone",
        name: "Tone",
        description: "Does the voice fit the audience the prompt asked for?",
        catches: "Rude, robotic, off-brand, too casual, too formal. The dimension hardest to eyeball at scale and the one most user-facing surfaces care about.",
        instruction: "Does the voice match the audience and brand the prompt called for? Reward outputs that sound like the persona the prompt asked for. Penalise rude, robotic, off-brand, or wrong-register replies.",
        rubric_bands: [
          { "stars" => 5, "description" => "Sounds like the brand or persona the prompt asked for." },
          { "stars" => 4, "description" => "Right tone with a slip or two." },
          { "stars" => 3, "description" => "Acceptable, generic, no personality." },
          { "stars" => 2, "description" => "Mismatched tone; sounds like a different audience." },
          { "stars" => 1, "description" => "Off-tone in a way a user would notice (rude, condescending, jarring)." }
        ]
      ),
      Starter.new(
        key: "conciseness",
        name: "Conciseness",
        description: "Is it the right length, no padding, no missing detail?",
        catches: "Rambling responses, repetitive caveats, over-hedging. LLMs default to verbose. Conciseness is the dimension where users most often see scores move after tuning.",
        instruction: "Is the output the right length for the task: no padding, no missing detail, no hedging filler? Penalise rambling, repetition, over-caveating, and unnecessary preamble. Penalise too-short outputs that drop information.",
        rubric_bands: [
          { "stars" => 5, "description" => "Exactly as long as the task needs, no more, no less." },
          { "stars" => 4, "description" => "Right length with a small redundancy." },
          { "stars" => 3, "description" => "Acceptable; trims could happen or detail could be added." },
          { "stars" => 2, "description" => "Noticeable filler or visible gaps." },
          { "stars" => 1, "description" => "Padded, repetitive, or so short it loses information." }
        ]
      )
    ].freeze

    module_function

    def find(key)
      ALL.find { |s| s.key == key }
    end

    def available
      adopted_names = Metric.where(name: ALL.map(&:name)).pluck(:name).to_set
      dismissed_keys = StarterMetricDismissal.pluck(:starter_key).to_set
      ALL.reject { |s| adopted_names.include?(s.name) || dismissed_keys.include?(s.key) }
    end

    def adopted?(starter)
      Metric.exists?(name: starter.name)
    end
  end
end
