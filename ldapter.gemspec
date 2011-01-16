Gem::Specification.new do |s|
  s.name                = "ldapter"
  s.version             = "0.1.0"

  s.summary             = 'Object Oriented Wrapper around LDAP and Net::LDAP'
  s.authors             = ["Tim Pope"]
  s.email               = "ruby@tpope.o"+'rg'
  s.homepage            = "http://github.com/tpope/ldapter"
  s.files = [ "Rakefile", "setup.rb", "LICENSE" ]
  s.files = s.files + Dir.glob( "lib/**/*.rb" )
  s.files = s.files + Dir.glob( "test/**/*" ).reject { |item| item.include?( "\.svn" ) }
end
