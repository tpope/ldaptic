Gem::Specification.new do |s|
  s.name                = "ldapter"
  s.version             = "0.1.0"

  s.summary             = 'Object Oriented Wrapper around LDAP and Net::LDAP'
  s.authors             = ["Tim Pope"]
  s.email               = "ruby@tpope.o"+'rg'
  s.homepage            = "http://github.com/tpope/ldapter"
  s.files = [ "Rakefile", "setup.rb", "README.rdoc", "LICENSE" ]
  s.files = s.files + Dir.glob("lib/**/*.rb")
  s.files = s.files + Dir.glob("test/**/*")

  s.add_development_dependency("ruby-ldap", "~> 0.9.0")
  s.add_development_dependency("net-ldap", "~> 0.1.0")
  s.add_development_dependency("activemodel", "~> 3.0.0")
end
