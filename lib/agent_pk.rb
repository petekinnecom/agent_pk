require "ruby_llm"

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup

# Configure i18n how I like it:

require "i18n"
MissingTranslation = Class.new(StandardError)
I18n.singleton_class.prepend(Module.new do
  def t(*a, **p)
    super(*a, __force_exception_raising__: true, **p)
  end
end)
I18n.exception_handler = ->(_, _, key, _) { raise MissingTranslation.new(key.inspect) }
I18n.load_path << File.join(__dir__, "./agent_pk/prompts.yml")

module AgentPk
  class Configuration
    attr_accessor(
      :db_path,
      :logger,
      :i18n_path,
      :workspace_dir,
      :project,
      :run_id
    )

    def workspace_dir
      @workspace_dir ||= Dir.pwd
    end
  end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield(config)

      if config.db_path
        raise "Must configure project" unless config.project
        config.run_id ||= Time.now.to_i

        AgentPk::Db.connect(config.db_path)
      end

      if config.i18n_path
        I18n.load_path << config.i18n_path
      end
    end

    def cost(project, run_id = nil)
      raise "Database must be configured" unless config.db_path

      AgentPk::Reports::Cost.call(
        project: project,
        run_id: run_id,
        out: $stdout
      )
    end
  end
end
