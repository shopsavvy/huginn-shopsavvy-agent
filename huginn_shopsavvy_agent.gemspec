Gem::Specification.new do |spec|
  spec.name          = 'huginn_shopsavvy_agent'
  spec.version       = '1.0.0'
  spec.authors       = ['ShopSavvy']
  spec.email         = ['support@shopsavvy.com']

  spec.summary       = 'Huginn agents for ShopSavvy price monitoring and deal discovery'
  spec.description   = 'Three Huginn agents that integrate with the ShopSavvy Data API: product lookup, price monitoring with drop alerts, and social deal discovery with deduplication.'
  spec.homepage      = 'https://github.com/shopsavvy/huginn-shopsavvy-agent'
  spec.license       = 'MIT'

  spec.metadata = {
    'homepage_uri'    => spec.homepage,
    'source_code_uri' => spec.homepage,
    'bug_tracker_uri' => "#{spec.homepage}/issues"
  }

  spec.files = Dir['lib/**/*', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.7.0'

  spec.add_runtime_dependency 'faraday', '>= 1.0', '< 3.0'
  spec.add_runtime_dependency 'faraday-net_http', '>= 1.0'

  spec.add_development_dependency 'huginn_agent', '~> 0.6'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
end
