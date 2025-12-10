require "ruby_llm/schema"

module AgentPk
  module Schema
    class AnyOneOf
      attr_reader :schemas
      def initialize(*schemas)
        @schemas = schemas
      end

      def to_nested_schema
        to_json_schema.fetch(:schema).fetch(:oneOf)
      end

      def schema_jsons
        @schema_jsons ||= (
          schemas.flat_map do |schema|
            if schema.is_a?(AnyOneOf)
              to_nested_schema
            elsif schema.ancestors.include?(RubyLLM::Schema)
              schema.new.to_json_schema.fetch(:schema)
            else
              raise ArgumentError, "Invalid schema class: #{schema}"
            end
          end
        )
      end

      def to_json_schema
        {
          schema: {
            oneOf: schema_jsons
          }
        }
      end
    end

    class ErrorSchema < RubyLLM::Schema
      string(
        :status,
        enum: ["error"],
      )

      string(
        :message,
        description: <<~TXT
          A brief description of the reason you could not fulfill the request.
        TXT
      )
    end

    def self.result(&)
      # Create the success schema
      success_schema = Class.new(RubyLLM::Schema) do
        string(
          :status,
          enum: ["success"],
        )

        instance_exec(&) if block_given?
      end

      AnyOneOf.new(success_schema, ErrorSchema)
    end
  end
end
