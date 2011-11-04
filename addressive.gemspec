Gem::Specification.new do |s|
  s.name = 'addressive'
  s.version = '0.0.1'
  s.date = '2011-10-31'
  s.authors = ["HannesG"]
  s.email = %q{hannes.georg@googlemail.com}
  s.summary = 'A system which should help bringing different Rack applications together.'
  s.homepage = 'http://github.com/hannesg/addressive'
  s.description = ''
  
  s.require_paths = ['lib']
  
  s.files = Dir.glob('lib/**/**/*.rb') + ['addressive.gemspec']
  
  s.add_dependency 'uri_template', '~> 0.1.0'
  
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'yard'
end
