
module AgentPk
  module Tools
    NAMES = {
      read_file: ReadFile,
      edit_file: EditFile,
      grep: Grep,
      file_metadata: FileMetadata,
      dir_glob: DirGlob,
      run_rails_test: RunRailsTest,
    }

    def self.all(**params)
      NAMES.keys.new(**params)
    end

    def self.resolve(name, **params)
      NAMES.fetch(name.to_sym).new(**params)
    end
  end
end
