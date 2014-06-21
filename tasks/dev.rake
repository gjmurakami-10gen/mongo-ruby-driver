PASSING_TESTS =  %w{
  basic
  client
  connection
  count
  max_values
  pinning
  query
  replication_ack
}

FAILING_TESTS = %w{
  authentication
  complex_connect
  cursor
  insert
  read_preference
  refresh
  ssl
}

# authentication - mongod without --auth, 3 failures
# complex_connect - @rs.start # excluded in testing.rake
# cursor - @read is nil # excluded in testing.rake
# insert - @rs.start
# read_preferences - @rs.config @rs.restart # excluded in testing.rake
# refresh_test - @rs.member_by_name @rs.restart @rs.stop_secondary # @rs.add_node(n) @rs.remove_secondary_node @rs.repl_set_remove_node(2)
# ssl - # excluded in testing.rake

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