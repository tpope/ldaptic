Gem::Specification.new do |s|
  s.name        = "ldaptic"
  s.version     = "0.1.2"

  s.summary     = 'Object-oriented schema-aware LDAP wrapper'
  s.description = 'Include a parameterized dynamic module in a namespace and get a full LDAP class hierarchy at your disposal.'
  s.authors     = ["Tim Pope"]
  s.email       = "ruby@tpope.o"+'rg'
  s.homepage    = "http://github.com/tpope/ldaptic"
  s.files       = ["Rakefile", "README.rdoc", "LICENSE"]
  s.files      += Dir.glob("lib/**/*.rb")
  s.files      += Dir.glob("test/**/*")

  s.add_development_dependency("ruby-ldap", "~> 0.9.0")
  s.add_development_dependency("net-ldap", "~> 0.1.0")
  s.add_development_dependency("activemodel", "~> 3.0.0")
end
