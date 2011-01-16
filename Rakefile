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

spec = eval(File.read(File.join(File.dirname(__FILE__),'ldapter.gemspec')))
Rake::GemPackageTask.new(spec) do |p|
  p.gem_spec = spec
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
