PASSING_TESTS =  %w{
  basic
  client
}

FAILING_TESTS = %w{
  authentication
  complex_connect
  connection
  count
  cursor
  insert
  max_values
  pinning
  query
  read_preference
  refresh
  replication_ack
  ssl
}

SKIP_TESTS = %w{
  framework
}

ALL_TESTS = PASSING_TESTS + FAILING_TESTS + SKIP_TESTS

namespace :dev do

  task :rs_passing do
    PASSING_TESTS.each do |test|
      sh "time ruby -Ilib -Itest test/replica_set/#{test}_test.rb -v"
    end
  end

end