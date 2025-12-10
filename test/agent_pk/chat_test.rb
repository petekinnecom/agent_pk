require "test_helper"
require "ruby_llm"
require "ostruct"

module AgentPk
  class ChatTest < Minitest::Test
    # DummyRecord that maps input_text => output_text for testing
    class DummyRecord
      attr_reader :id, :messages_history

      def initialize(responses: {})
        @responses = responses
        @id = "test-chat-#{rand(1000)}"
        @messages_history = []
      end

      def ask(input_text)
        # Try to find a matching response
        output_text = nil

        @responses.each do |key, value|
          if key.is_a?(Regexp) && input_text.match?(key)
            output_text = value
            break
          elsif key.is_a?(Proc) && key.call(input_text)
            output_text = value
            break
          elsif key == input_text
            output_text = value
            break
          end
        end

        raise "No response configured for: #{input_text.inspect}" if output_text.nil?

        # Create a mock message with the input
        user_message = OpenStruct.new(
          role: :user,
          content: input_text,
          to_llm: OpenStruct.new(to_h: { role: :user, content: input_text })
        )

        # Create a mock response message
        response_message = OpenStruct.new(
          role: :assistant,
          content: output_text,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: output_text })
        )

        @messages_history << user_message
        @messages_history << response_message

        response_message
      end

      def messages(...)
        @messages_history
      end

      def with_tools(*tools)
        self
      end

      def on_new_message(&block)
        self
      end

      def on_end_message(&block)
        self
      end

      def on_tool_call(&block)
        self
      end

      def on_tool_result(&block)
        self
      end
    end

    def setup
      AgentPk.configure do |config|
        config.project = "test"
        config.run_id = "test-run"
        config.workspace_dir = "/tmp/test"
        config.logger = Logger.new(nil) # Suppress logging in tests
      end
    end

    def test_ask_returns_configured_response
      record = DummyRecord.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = Chat.new(record: record)
      response = chat.ask("Hello")

      assert_equal "Hi there!", response.content
    end

    def test_ask_with_multiple_responses
      record = DummyRecord.new(responses: {
        "What is 2+2?" => "4",
        "What is the capital of France?" => "Paris"
      })

      chat = Chat.new(record: record)

      response1 = chat.ask("What is 2+2?")
      assert_equal "4", response1.content

      response2 = chat.ask("What is the capital of France?")
      assert_equal "Paris", response2.content
    end

    def test_ask_raises_for_unknown_input
      record = DummyRecord.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = Chat.new(record: record)

      error = assert_raises(RuntimeError) do
        chat.ask("Unknown input")
      end

      assert_match(/No response configured for/, error.message)
    end

    def test_id_returns_record_id
      record = DummyRecord.new(responses: {})
      chat = Chat.new(record: record)

      assert_equal record.id, chat.id
    end

    def test_to_h_returns_message_history
      record = DummyRecord.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = Chat.new(record: record)
      chat.ask("Hello")

      history = chat.to_h

      assert_equal 2, history.length
      assert_equal :user, history[0][:role]
      assert_equal "Hello", history[0][:content]
      assert_equal :assistant, history[1][:role]
      assert_equal "Hi there!", history[1][:content]
    end

    def test_get_with_valid_json_schema
      record = DummyRecord.new(responses: {
        ->(text) { text.include?("Get person data") } => '{"status": "success", "name": "Alice", "age": 30}'
      })

      chat = Chat.new(record: record)

      schema = Schema.result do
        string(:name, description: "Person's name")
        integer(:age, description: "Person's age")
      end

      result = chat.get("Get person data", schema: schema)

      assert_equal "Alice", result["name"]
      assert_equal 30, result["age"]
    end

    def test_get_with_confirmation
      # Test that get waits for confirmed answer
      call_count = 0
      record = DummyRecord.new(responses: {})

      # Override ask to return different answers
      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        answer = call_count == 1 ? '{"status": "success", "value": "A"}' : '{"status": "success", "value": "A"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = Chat.new(record: record)

      schema = Schema.result do
        string(:value, description: "A value")
      end

      result = chat.get("Get value", schema: schema, confirm: 2, out_of: 2)

      assert_equal "A", result["value"]
      assert_equal 2, call_count
    end

    def test_refine_makes_multiple_attempts
      call_count = 0
      record = DummyRecord.new(responses: {})

      # Override ask to track refinement
      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        answer = '{"status": "success", "result": "refined answer"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = Chat.new(record: record)

      schema = Schema.result do
        string(:result, description: "The result")
      end

      result = chat.refine("Give me an answer", schema: schema, times: 2)

      assert_equal "refined answer", result["result"]
      assert_equal 2, call_count
    end

    def test_messages_returns_message_history
      record = DummyRecord.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = Chat.new(record: record)
      chat.ask("Hello")

      messages = chat.messages

      assert_equal 2, messages.length
      assert_equal "Hello", messages[0].content
      assert_equal "Hi there!", messages[1].content
    end

    def test_chat_with_custom_tools
      record = DummyRecord.new(responses: {
        "Test" => "Response"
      })

      custom_tools = [Tools::ReadFile.new]
      chat = Chat.new(record: record, tools: custom_tools)

      assert_equal 1, chat.tools.length
      assert_instance_of Tools::ReadFile, chat.tools.first
    end

    def test_chat_with_custom_prompts
      record = DummyRecord.new(responses: {
        "Test" => "Response"
      })

      prompts = ["You are a helpful assistant"]
      chat = Chat.new(record: record, prompts: prompts)

      assert_equal prompts, chat.prompts
    end

    def test_get_with_invalid_json_then_valid
      # Test retry logic when first response is invalid JSON
      call_count = 0
      record = DummyRecord.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        # First call returns invalid JSON, second returns valid
        answer = call_count == 1 ? 'invalid json' : '{"status": "success", "data": "valid"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = Chat.new(record: record)

      schema = Schema.result do
        string(:data, description: "Some data")
      end

      result = chat.get("Get data", schema: schema)

      assert_equal "valid", result["data"]
      assert_equal 2, call_count
    end

    def test_get_with_schema_violation_then_valid
      # Test retry logic when first response doesn't match schema
      call_count = 0
      record = DummyRecord.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        # First call returns JSON that doesn't match schema, second returns valid
        answer = call_count == 1 ? '{"status": "success"}' : '{"status": "success", "data": "valid"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = Chat.new(record: record)

      schema = Schema.result do
        string(:data, description: "Some data")
      end

      result = chat.get("Get data", schema: schema)

      assert_equal "valid", result["data"]
      assert_equal 2, call_count
    end

    def test_get_with_error_response
      # Test error response from schema
      record = DummyRecord.new(responses: {
        ->(text) { text.include?("impossible task") } => '{"status": "error", "message": "Cannot complete this task"}'
      })

      chat = Chat.new(record: record)

      schema = Schema.result do
        string(:data, description: "Some data")
      end

      result = chat.get("Do an impossible task", schema: schema)

      assert_equal "error", result["status"]
      assert_equal "Cannot complete this task", result["message"]
    end

    def test_refine_with_second_refinement_different
      # Test that refine includes prior answer in subsequent requests
      call_count = 0
      prior_answer_found = false
      record = DummyRecord.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1

        # Second request should include the prior answer
        if call_count == 2
          expected_prompt = I18n.t(
            "agent.chat.refine.system_message",
            prior_answer: '{"status": "success", "result": "first answer"}',
            original_message: "Give me an answer"
          )
          prior_answer_found = input_text.include?("BEGIN-PRIOR-ANSWER") && input_text.include?("first answer")
        end

        answer = call_count == 1 ? '{"status": "success", "result": "first answer"}' : '{"status": "success", "result": "refined answer"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = Chat.new(record: record)

      schema = Schema.result do
        string(:result, description: "The result")
      end

      result = chat.refine("Give me an answer", schema: schema, times: 2)

      assert_equal "refined answer", result["result"]
      assert_equal 2, call_count
      assert prior_answer_found, "Second refinement should include prior answer"
    end

    def test_get_with_no_confirmation_reached
      # Test that get raises when confirmation threshold not met
      call_count = 0
      record = DummyRecord.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        # Each call returns a different answer
        answer = '{"status": "success", "value": "' + "answer#{call_count}" + '"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = Chat.new(record: record)

      schema = Schema.result do
        string(:value, description: "A value")
      end

      error = assert_raises(RuntimeError) do
        chat.get("Get value", schema: schema, confirm: 2, out_of: 3)
      end

      assert_match(/Unable to confirm an answer/, error.message)
      assert_equal 3, call_count
    end

    def test_get_with_nil_schema
      # Test that get works without a schema
      record = DummyRecord.new(responses: {
        ->(text) { text.include?("Get unstructured data") } => '{"result": "some data"}'
      })

      chat = Chat.new(record: record)

      result = chat.get("Get unstructured data", schema: nil)

      assert_equal "some data", result["result"]
    end

    def test_get_result_max_retries_exceeded
      # Test that get_result raises after 5 failed attempts
      call_count = 0
      record = DummyRecord.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        # Always return invalid JSON
        answer = 'this is not valid json at all'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = Chat.new(record: record)

      schema = Schema.result do
        string(:data, description: "Some data")
      end

      error = assert_raises(RuntimeError) do
        chat.get("Get data", schema: schema)
      end

      assert_match(/Failed to get valid response/, error.message)
      assert_equal 5, call_count
    end

    def test_to_h_with_tool_calls
      # Test that to_h properly handles messages with tool_calls
      record = DummyRecord.new(responses: {})

      # Create a mock message with tool_calls
      tool_call = OpenStruct.new(to_h: { name: "test_tool", arguments: { arg: "value" } })
      tool_calls_hash = { "call_1" => tool_call }

      message_with_tools = OpenStruct.new(
        role: :assistant,
        content: "Using tools",
        to_llm: OpenStruct.new(
          to_h: {
            role: :assistant,
            content: "Using tools",
            tool_calls: tool_calls_hash
          }
        )
      )

      record.instance_variable_set(:@messages_history, [message_with_tools])

      chat = Chat.new(record: record)

      history = chat.to_h

      assert_equal 1, history.length
      assert_equal :assistant, history[0][:role]
      assert history[0].key?(:tool_calls)
      assert_equal 1, history[0][:tool_calls].length
      assert_equal "test_tool", history[0][:tool_calls][0][:name]
    end

    def test_normalize_schema_with_any_one_of
      # Test that AnyOneOf schema from Schema.result works correctly
      record = DummyRecord.new(responses: {
        ->(text) { text.include?("Get data") } => '{"status": "success", "value": "test"}'
      })

      chat = Chat.new(record: record)

      # Schema.result already returns an AnyOneOf
      schema = Schema.result do
        string(:value, description: "A value")
      end

      assert_instance_of Schema::AnyOneOf, schema

      result = chat.get("Get data", schema: schema)

      assert_equal "test", result["value"]
    end
  end
end
