
module AgentPk
  module Chats
    module AnthropicBedrock
      def self.create(project:, run_id:, prompts:)
        AgentPk::Db::Chat
          .create!(
            model: AgentPk::Db::Model.find_or_create_by!(
              model_id: RubyLLM.config.default_model,
              provider: "bedrock"
            ) { |m|
              m.name = "Claude Sonnet 4.5"
              m.family = "claude"
            },
            project: AgentPk.config.project,
            run_id: AgentPk.config.run_id
          )
          .tap { |chat|
            if prompts.any?
              # WARN -- RubyLLM: Anthropic's Claude implementation only supports
              # a single system message. Multiple system messages will be
              # combined into one.
              shared_prompt = prompts.join("\n---\n")
              chat.messages.create!(
                role: :system,
                content_raw: [
                  {
                    "type" => "text",
                    "text" => shared_prompt,
                    "cache_control" => { "type" => "ephemeral" }
                  }
                ]
              )
            end
          }
      end
    end
  end
end
