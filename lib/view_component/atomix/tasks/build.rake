# frozen_string_literal: true

namespace :view_component do
  namespace :atomix do
    desc "Compile all ViewComponent::Atomix rules into a CSS file"
    task build: :environment do
      Rails.application.eager_load!
      ViewComponent::Atomix.eager_load!
      ViewComponent::Atomix.compile_dynamic_styles!
      path = ViewComponent::Atomix.write_css(force: true)
      puts "Wrote #{ViewComponent::Atomix.registry.size} rules to #{path}"
    end
  end
end

task "assets:precompile"
Rake::Task["assets:precompile"].prerequisites.unshift("view_component:atomix:build")
