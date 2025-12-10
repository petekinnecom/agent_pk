module AgentPk
  module Tools
    class DirGlob < RubyLLM::Tool
      description("Find files in a directory using a ruby-compatible glob pattern.")

      params do
        string(
          :glob_pattern,
          description: "Only returns children paths of the current directory"
        )
      end

      attr_reader :working_dir
      def initialize(working_dir: AgentPk.config.workspace_dir)
        @working_dir = working_dir
      end

      def execute(glob_pattern:)
        unless Paths.allowed?(working_dir, glob_pattern)
          return "Path: #{glob_pattern} not acceptable. Must be a child of directory: #{working_dir}."
        end

        Dir
          .glob(glob_pattern)
          .select { Paths.allowed?(_1) }
          .to_json
      end
    end
  end
end
