require "active_record"
require "sqlite3"
require "logger"
require "test_helper"

module AgentPk
  class DbTest < Minitest::Test
    def setup
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::WARN

      # Configure Agent with DB path and logger
      AgentPk.configure do |config|
        config.db_path = DB_PATH
        config.logger = @logger
      end

      # Configure RubyLLM with mock credentials for testing
      RubyLLM.configure do |config|
        config.bedrock_api_key = "test-key"
        config.bedrock_secret_key = "test-secret"
        config.bedrock_region = "us-west-2"
        config.default_model = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
      end
    end

    def teardown
      # Cleanup test database
      File.delete("/tmp/other_test.sqlite3") if File.exist?("/tmp/other_test.sqlite3")
      remove_const_if_exists(:OtherBase)
    end

    # Persistence tests
    def test_chat_creation_with_persistence
      chat = Chat.new(tools: [], prompts: [])

      refute_nil chat.id, "Chat should have an ID"
      refute_nil chat.record, "Chat should have a record"
      refute_nil chat.record.id, "Chat record should have an ID"
      refute_nil chat.record.model, "Chat should have a model"
    end

    def test_llm_model_has_provider_and_name
      chat = Chat.new(tools: [], prompts: [])
      model = chat.record.model

      refute_nil model.name, "Model should have a name"
      refute_nil model.provider, "Model should have a provider"
    end

    def test_database_tables_exist
      expected_tables = ["chats", "messages", "models"]
      actual_tables = Db::LlmBase.connection.tables.sort

      expected_tables.each do |table|
        assert_includes actual_tables, table, "Database should have #{table} table"
      end
    end

    def test_chat_and_message_counts
      initial_chat_count = Db::Chat.count
      initial_message_count = Db::Message.count
      initial_model_count = Db::Model.count

      chat = Chat.new(tools: [], prompts: [])
      # Force the record to be created by accessing it
      chat.record

      assert_operator Db::Chat.count, :>=, initial_chat_count + 1, "Chat count should increase"
      assert_operator Db::Model.count, :>=, initial_model_count, "Model count should stay same or increase"
      # Messages may or may not be created during initialization
      assert_operator Db::Message.count, :>=, initial_message_count, "Message count should not decrease"
    end

    def test_messages_are_persisted
      chat = Chat.new(tools: [], prompts: [])

      # The chat object should have a reference to its persisted messages
      assert_respond_to chat.record, :messages, "Chat record should have messages association"

      # If there are messages, they should have expected attributes
      if chat.record.messages.any?
        message = chat.record.messages.first
        assert_respond_to message, :role, "Message should have role"
        assert_respond_to message, :content, "Message should have content"
        assert_includes ["system", "user", "assistant"], message.role, "Message role should be valid"
      end
    end

    def test_database_path_is_set
      refute_nil DB_PATH, "DB_PATH constant should be defined"
      assert_kind_of String, DB_PATH, "DB_PATH should be a string"
      assert_match(/\.sqlite3$/, DB_PATH, "DB_PATH should point to a SQLite database")
    end

    # Multi-database tests
    def test_separate_base_classes
      # Create a separate database with its own base class
      skip_if_other_base_exists

      Object.const_set(:OtherBase, Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end)

      ::OtherBase.establish_connection(
        adapter: "sqlite3",
        database: "/tmp/other_test.sqlite3"
      )

      llm_db = Db::LlmBase.connection.instance_variable_get(:@config)[:database]
      other_db = ::OtherBase.connection.instance_variable_get(:@config)[:database]

      refute_equal llm_db, other_db, "Database paths should be different"
      assert_match(/\.sqlite3$/, llm_db.to_s, "LlmBase should use a SQLite database")
      assert_equal "/tmp/other_test.sqlite3", other_db, "OtherBase should use test database"
    end

    def test_agent_db_models_use_correct_database
      expected_db = Db::LlmBase.connection.instance_variable_get(:@config)[:database]

      assert_equal "chats", Db::Chat.table_name
      assert_equal expected_db, Db::Chat.connection.instance_variable_get(:@config)[:database]
      assert_equal expected_db, Db::Model.connection.instance_variable_get(:@config)[:database]
      assert_equal expected_db, Db::Message.connection.instance_variable_get(:@config)[:database]
    end

    def test_create_records_on_llm_database
      initial_count = Db::Chat.count

      chat = Chat.new(tools: [])

      refute_nil chat.record
      refute_nil chat.record.id
      assert_equal initial_count + 1, Db::Chat.count
    end

    def test_connections_are_independent
      skip_if_other_base_exists

      Object.const_set(:OtherBase, Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end)

      ::OtherBase.establish_connection(
        adapter: "sqlite3",
        database: "/tmp/other_test.sqlite3"
      )

      llm_connection_id = Db::LlmBase.connection.object_id
      other_connection_id = ::OtherBase.connection.object_id

      refute_equal llm_connection_id, other_connection_id, "Connections should be different objects"
    end

    def test_active_record_base_is_not_configured
      assert_raises(ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionNotDefined) do
        ActiveRecord::Base.connection
      end
    end

    private

    def skip_if_other_base_exists
      skip "OtherBase already defined" if Object.const_defined?(:OtherBase)
    end

    def remove_const_if_exists(const_name)
      Object.send(:remove_const, const_name) if Object.const_defined?(const_name)
    end
  end
end
