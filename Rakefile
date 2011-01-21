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
$:.unshift(File.join(File.dirname(__FILE__), 'lib'))
require 'ldapter'

desc "Default task: test"
task :default => [ :test ]

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = Dir['test/*_test.rb']
  t.verbose = true
end

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = 'doc'
  rdoc.rdoc_files.add('README.rdoc', 'lib')
  rdoc.main     = 'README.rdoc'
  rdoc.title    = 'Ldapter'
  rdoc.options << '--inline-source'
  rdoc.options << '-d' if `which dot` =~ /\/dot/
end

desc "Generate the RDoc documentation for RI"
task :ri do
  system("rdoc","--ri","lib")
end

spec = eval(File.read(File.join(File.dirname(__FILE__),'ldapter.gemspec')))
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
