# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "watti_watchman"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

file :schema do |t|
  mkdir_p "dist"
  File.write(
    File.join("dist/schema.json"),
    Oj.dump(
      WattiWatchman::Config.load({}).schemer.bundle,
      mode: :compat,
      indent: 2
    )
  )
end
