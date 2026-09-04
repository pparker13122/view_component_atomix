# frozen_string_literal: true

require_relative "lib/view_component/styles/version"

Gem::Specification.new do |spec|
  spec.name = "view_component_styles"
  spec.version = ViewComponent::Styles::VERSION
  spec.authors = ["Peter Park"]
  spec.email = ["github@peterpark.io"]

  spec.summary = "StyleX-style atomic CSS for ViewComponent and Rails"
  spec.description = "Define styles as Ruby hashes next to your components. Compiles to deterministic atomic classes with per-property merging, conditions, breakpoints, dynamic values and CSS-variable theming. No JavaScript build step."
  spec.homepage = "https://github.com/peterpark/view_component_styles"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "actionview", ">= 7.0"
  spec.add_dependency "railties", ">= 7.0"
  spec.add_dependency "zeitwerk", ">= 2.6.2"
  spec.add_dependency "view_component", "~> 3.0"
end
