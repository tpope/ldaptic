begin
  require 'rubygems'
rescue LoadError
end
require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/packagetask'
require 'rake/gempackagetask'
require 'rake/contrib/sshpublisher'
require File.join(File.dirname(__FILE__), 'lib', 'ldapter')

PKG_BUILD     = ENV['PKG_BUILD'] ? '.' + ENV['PKG_BUILD'] : ''
PKG_NAME      = 'ldapter'
PKG_VERSION   = "0.1" + PKG_BUILD

desc "Default task: test"
task :default => [ :test ]

Rake::TestTask.new { |t|
  t.libs << "test"
  t.test_files = Dir['test/*_test.rb'] + Dir['test/test_*.rb']
  t.verbose = true
}

Rake::RDocTask.new { |rdoc|
  rdoc.rdoc_dir = 'doc'
  rdoc.rdoc_files.add('lib')
  rdoc.main     = "Ldapter"
  rdoc.title    = "Ldapter"
  rdoc.options << '--inline-source'
  rdoc.options << '-d' if `which dot` =~ /\/dot/
}

desc "Generate the RDoc documentation for RI"
task :ri do
  system("rdoc","--ri","lib")
end

spec = Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = PKG_NAME
  s.summary = 'Object Oriented Wrapper around LDAP and Net::LDAP.'
  s.description = 'Object Oriented Wrapper around LDAP and Net::LDAP.'
  s.version = PKG_VERSION

  s.author = 'Tim Pope'
  s.email = 'r*by@tpope.in#o'.tr('*#','uf')
  s.rubyforge_project = RUBY_FORGE_PROJECT

  s.has_rdoc = true
  s.require_path = 'lib'

  s.files = [ "Rakefile", "setup.rb" ]
  s.files = s.files + Dir.glob( "lib/**/*.rb" )
  s.files = s.files + Dir.glob( "test/**/*" ).reject { |item| item.include?( "\.svn" ) }
end

Rake::GemPackageTask.new(spec) do |p|
  p.gem_spec = spec
  p.need_tar = true
  p.need_zip = true
end

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |t|
    t.test_files = Dir['test/*_test.rb'] + Dir['test/test_*.rb']
    t.verbose = true
    t.rcov_opts << "--exclude '/(ruby-net-ldap|active_support)\\b'"
  end
rescue LoadError
end
