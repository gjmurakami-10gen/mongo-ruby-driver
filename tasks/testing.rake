require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)
task :default => :spec

namespace :spec do
  if RUBY_VERSION > '1.9' && RUBY_VERSION < '2.2'
    require 'coveralls/rake/task'
    Coveralls::RakeTask.new
    task :ci => [:spec, 'coveralls:push']
  else
    task :ci => [:spec]
  end
end

task :features do |t|
  mkdir_p('features')
  sh "cd features && svn checkout https://github.com/mongodb/mongo-meta-driver/trunk/features/topology"
end

desc "Run Common Topology Test Suite"
task :topology do |t|
  sh "cucumber -b -r features/step_definitions -r features/support features/topology --tag ~@pending --tag ~@ruby_2_x_broken"
end
