# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

namespace :spec do
  desc "Run core specs without booting the Rails application"
  RSpec::Core::RakeTask.new(:core) do |task|
    task.pattern = "spec/core/**/*_spec.rb"
  end
end

task default: :spec
