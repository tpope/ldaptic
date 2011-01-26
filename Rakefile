begin
  require 'rubygems'
rescue LoadError
end
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/packagetask'
require 'rake/gempackagetask'
$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

task :default => :test

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = Dir['test/*_test.rb']
  t.verbose = true
end

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = 'doc'
  rdoc.rdoc_files.add('README.rdoc', 'lib')
  rdoc.main     = 'README.rdoc'
  rdoc.title    = 'Ldaptic'
  rdoc.options << '--inline-source'
  rdoc.options << '-d' if `which dot` =~ /\/dot/
end

spec = eval(File.read(File.join(File.dirname(__FILE__), 'ldaptic.gemspec')))
Rake::GemPackageTask.new(spec) do |p|
  p.gem_spec = spec
end

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |t|
    t.test_files = Dir['test/*_test.rb']
    t.verbose = true
    t.rcov_opts << "--exclude '/(rcov|net-ldap|i18n|active(?:support|model))-'"
  end
rescue LoadError
end
