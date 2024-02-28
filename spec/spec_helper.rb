# frozen_string_literal: true

require 'rspec/mocks'
require 'faker'

require "simplecov"
require "simplecov-json"
SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::JSONFormatter
])
SimpleCov.start do
  enable_coverage :branch
end

def deep_load(scope)
  return unless scope.respond_to?(:constants)
  scope.constants.each do |const|
    next unless scope.autoload?(const)
    deep_load(scope.const_get(const))
  end
end

require "watti_watchman"

RSpec.shared_context "meter" do
  def iterations(rounds)
    allow_any_instance_of(described_class).to(
      receive(:loop) do |&block|
        rounds.times { block.call }
      end
    )
  end

  def mcache
    WattiWatchman::Meter.cache
  end
end


RSpec.shared_context "logger" do
  let :unit_logger do
    StringIO.new
  end

  before(:each) do
    allow_any_instance_of(described_class).to receive(:logger) do
      Logger.new(unit_logger)
    end
    allow(described_class).to receive(:logger) do
      Logger.new(unit_logger)
    end
  end
end

RSpec.shared_context "meter-reset" do
  before(:each) do
    WattiWatchman::Meter.instance_variable_set(:@cache, nil)
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include_context "logger"
  config.include_context "meter-reset"
end

Faker::Config.random = Random.new(RSpec.configuration.seed)
