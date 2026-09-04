# frozen_string_literal: true

namespace :view_component do
  namespace :styles do
    desc "Compile all ViewComponent::Styles rules into a CSS file"
    task build: :environment do
      Rails.application.eager_load!
      ViewComponent::Styles.eager_load!
      ViewComponent::Styles.compile_dynamic_styles!
      path = ViewComponent::Styles.write_css(force: true)
      puts "Wrote #{ViewComponent::Styles.registry.size} rules to #{path}"
    end
  end
end

task "assets:precompile"
Rake::Task["assets:precompile"].prerequisites.unshift("view_component:styles:build")
