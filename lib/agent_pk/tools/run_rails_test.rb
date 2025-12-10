require "shellwords"

module AgentPk
  module Tools
    class RunRailsTest < RubyLLM::Tool
      description "Runs a minitest rails test using bin/rails test {path} --name={name_of_test_method}"

      params do
        string(
          :path,
          description: "Path to file. Must be a child of current directory.",
          required: true
        )
        string(
          :test_method_name,
          description: "The name of the specific test method to run",
          required: false
        )
      end

      attr_reader :working_dir, :env
      def initialize(
        working_dir: AgentPk.config.workspace_dir,
        env: {}
      )
        @env = env
        @working_dir = working_dir
      end

      def execute(path:, test_method_name: nil)
        unless Paths.allowed?(working_dir, path)
          return "Path: #{path} not acceptable. Must be a child of directory: #{working_dir}."
        end

        workspace_path = Paths.relative_to_dir(working_dir, path)

        env_string = env.is_a?(Hash) ? env.map { |k, v| "#{k}=#{Shellwords.escape(v)}"}.join(" ") : env

        cmd = <<~TXT.chomp
          cd #{working_dir} && \
          DISABLE_SPRING=1 #{env} bundle exec rails test #{path} #{test_method_name && "--name='#{test_method_name}'"}
        TXT

        lines = []
        result = nil
        Bundler.with_original_env do
          result = shell.run(cmd) do |stream, line|
            lines << "[#{stream}] #{line}"
          end
        end

        return <<~TXT
          Command exited #{result.success? ? "successfully" : "with non-zero exit code"}
          ---
          #{lines.join("\n")}
        TXT
      end

      def shell
        ConcurrentPipeline::Shell
      end
    end
  end
end
