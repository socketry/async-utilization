# frozen_string_literal: true

require_relative "lib/async/utilization/version"

Gem::Specification.new do |spec|
	spec.name = "async-utilization"
	spec.version = Async::Utilization::VERSION
	
	spec.summary = "High-performance utilization metrics for Async services using shared memory."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/async-utilization"
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/async-utilization/",
		"source_code_uri" => "https://github.com/socketry/async-utilization.git",
	}
	
	spec.files = Dir.glob(["{lib,test}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__)
	
	spec.required_ruby_version = ">= 3.2"
	
	spec.add_dependency "console", "~> 1.0"
	spec.add_dependency "thread-local", "~> 1.0"
end
