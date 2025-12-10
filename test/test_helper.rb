require "bundler/setup"
require "minitest/autorun"
require "logger"

# Test helper to set up common test environment
ENV["RACK_ENV"] = "test"

require "agent_pk"

AgentPk.configure do |config|
  config.project = "test"
end

# Define test database path
DB_PATH = File.expand_path("../tmp/db/test.sqlite3", __dir__)

# Optional: Add minitest reporters for better output
begin
  require "minitest/reporters"
  Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
rescue LoadError
  # minitest/reporters not available, use default output
end
