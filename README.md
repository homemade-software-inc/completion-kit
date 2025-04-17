# CompletionKit

CompletionKit is a GenAI prompt testing platform that can be mounted as a Rails engine in Rails 7 and 8 applications. It provides a comprehensive solution for testing and evaluating LLM prompts with variable data.

## Features

- Create prompt templates with variable placeholders
- Upload CSV data with values for those variables
- Run tests against various LLM models (OpenAI, Anthropic, Llama)
- Evaluate the quality of outputs using an LLM judge
- Sort and filter test results by quality score
- Compare outputs with expected results

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'completion_kit'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install completion_kit
```

## Configuration

### Mount the Engine

Add the following to your `config/routes.rb` file:

```ruby
Rails.application.routes.draw do
  mount CompletionKit::Engine => "/completion_kit"
end
```

### API Keys

CompletionKit requires API keys for the LLM providers you want to use. Set these in your environment variables:

```ruby
# For OpenAI (GPT models)
ENV['OPENAI_API_KEY'] = 'your_openai_api_key'

# For Anthropic (Claude models)
ENV['ANTHROPIC_API_KEY'] = 'your_anthropic_api_key'

# For Llama models
ENV['LLAMA_API_KEY'] = 'your_llama_api_key'
ENV['LLAMA_API_ENDPOINT'] = 'your_llama_api_endpoint'
```

**IMPORTANT**: To run test runs successfully, you must set at least one API key matching your selected model.

You have several options for configuring API keys:

1. **Environment variables** when starting your Rails server:

```bash
OPENAI_API_KEY=sk-your-key-here bin/rails server
```

2. **Using a .env file** in your Rails application root:

```
# .env file (add to .gitignore to keep keys secure)
OPENAI_API_KEY=sk-your-key-here
ANTHROPIC_API_KEY=sk-your-anthropic-key
```

3. **Direct configuration** in the initializer (config/initializers/completion_kit.rb):

  ```ruby
  CompletionKit.configure do |config|
    # Environment variable (recommended)
    config.openai_api_key = ENV['OPENAI_API_KEY']
    
    # Rails secrets (config/secrets.yml):
    # secrets.yml ->
    # development:
    #   completion_kit:
    #     openai_api_key: 'your-api-key-here'
    # config.openai_api_key = Rails.application.secrets.completion_kit[:openai_api_key]
    
    # Rails credentials (config/credentials.yml.enc):
    # credentials.yml.enc ->
    # completion_kit:
    #   openai_api_key: 'your-api-key-here'
    # config.openai_api_key = Rails.application.credentials.completion_kit[:openai_api_key]
  end
  ```

We recommend using option #2 with a .env file that is ignored by git for development.

### Database Migrations

Run the migrations to set up the necessary database tables:

```bash
$ bin/rails completion_kit:install:migrations
$ bin/rails db:migrate
```

## Usage

### Creating Prompts

1. Navigate to `/completion_kit/prompts`
2. Click "New Prompt"
3. Fill in the prompt template using `{{variable}}` syntax for placeholders
4. Select the LLM model to use
5. Save the prompt

### Running Tests

1. Navigate to a prompt's detail page
2. Click "New Test Run"
3. Upload CSV data with columns matching the variable names in your prompt
4. Run the tests
5. View and evaluate the results

### CSV Format

Your CSV data should include columns that match the variable names in your prompt template. For example:

```
input,expected_output
"Summarize this paragraph...","A concise summary..."
"Explain the concept of...","The concept refers to..."
```

The `expected_output` column is optional but recommended for better evaluation.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/completionkit/completion_kit.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
