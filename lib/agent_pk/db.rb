require "active_record"
require "sqlite3"
require "fileutils"

require "ruby_llm"
require "ruby_llm/active_record/acts_as"

module AgentPk
  module Db
    def self.connect(path)
      RubyLLM.configure do |config|
        config.use_new_acts_as = true
      end

      LlmBase.establish_connection(
        adapter: "sqlite3",
        database: path
      )

      LlmBase.connection_pool.with_connection do |connection|
        migration = Migration.new
        migration.verbose = false
        AgentPk.config.logger.info("Running database migrations...")
        migration.exec_migration(connection, :up)
        AgentPk.config.logger.info("Database migrations completed")
      end
    end

    class Migration < ActiveRecord::Migration[7.0]
      def self.up
        return if table_exists?(:chats)

        # Create models table first (referenced by chats and messages)
        create_table :models do |t|
          t.string :model_id, null: false
          t.string :name, null: false
          t.string :provider, null: false
          t.string :family
          t.datetime :model_created_at
          t.integer :context_window
          t.integer :max_output_tokens
          t.date :knowledge_cutoff
          t.json :modalities, default: {}
          t.json :capabilities, default: []
          t.json :pricing, default: {}
          t.json :metadata, default: {}
          t.timestamps

          t.index [:provider, :model_id], unique: true
          t.index :provider
          t.index :family
        end

        # Create chats table
        create_table :chats do |t|
          t.references :model, foreign_key: true
          t.string :project
          t.string :run_id
          t.timestamps
        end

        # Create messages table
        create_table :messages do |t|
          t.references :chat, null: false, foreign_key: true
          t.references :model, foreign_key: true
          t.references :tool_call, foreign_key: true
          t.string :role, null: false
          t.text :content
          t.json :content_raw
          t.integer :input_tokens
          t.integer :output_tokens
          t.integer :cached_tokens
          t.integer :cache_creation_tokens
          t.timestamps

          t.index :role
        end

        # Create tool_calls table
        create_table :tool_calls do |t|
          t.references :message, null: false, foreign_key: true
          t.string :tool_call_id, null: false
          t.string :name, null: false
          t.json :arguments, default: {}
          t.timestamps

          t.index :tool_call_id, unique: true
          t.index :name
        end
      end

      def self.down
        drop_table :tool_calls if table_exists?(:tool_calls)
        drop_table :messages if table_exists?(:messages)
        drop_table :chats if table_exists?(:chats)
        drop_table :models if table_exists?(:models)
      end
    end

    class LlmBase < ActiveRecord::Base
      self.abstract_class = true
      include RubyLLM::ActiveRecord::ActsAs
    end

    class Model < LlmBase
      self.table_name = "models"
      acts_as_model chats: :chats, chat_class: "AgentPk::Db::Chat"
    end

    # Model for chats
    class Chat < LlmBase
      self.table_name = "chats"
      acts_as_chat(
        messages: :messages,
        message_class: "AgentPk::Db::Message",
        messages_foreign_key: :chat_id,
        model: :model,
        model_class: "AgentPk::Db::Model",
        model_foreign_key: :model_id
      )

      validates :model, presence: true
    end

    # Model for messages
    class Message < LlmBase
      self.table_name = "messages"
      acts_as_message(
        chat: :chat,
        chat_class: "AgentPk::Db::Chat",
        chat_foreign_key: :chat_id,
        tool_calls: :tool_calls,
        tool_call_class: "AgentPk::Db::ToolCall",
        tool_calls_foreign_key: :message_id,
        model: :model,
        model_class: "AgentPk::Db::Model",
        model_foreign_key: :model_id
      )

      validates :role, presence: true
      validates :chat, presence: true
      # Note: Cannot validate content presence due to RubyLLM's persistence flow
    end

    # Model for tool calls
    class ToolCall < LlmBase
      self.table_name = "tool_calls"
      acts_as_tool_call(
        message: :message,
        message_class: "AgentPk::Db::Message",
        message_foreign_key: :message_id,
        result: :result,
        result_class: "AgentPk::Db::Message"
      )
    end
  end
end
