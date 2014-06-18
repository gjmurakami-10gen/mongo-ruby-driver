require 'rubygems'
gem 'test-unit' # necessary for startup and shutdown
require 'test_helper'
require 'json'
require 'pty'

# Mongo::Shell should be extracted into a separate file but is left here for the purposes of demonstration for now
module Mongo
  # A Mongo shell with methods for communication and testing convenience.
  # Note that this uses IO to a mongo shell, requiring synchronous IO with delimiters such as the prompt "> ".
  # This is problematic since the prompt or expected result can be mutilated by asynchronous output from other processes.
  class Shell
    CMD = %w{mongo --nodb --shell}
    PROMPT = %r{> }m
    PROMPT_EOS = %r{> $}m
    CHA_S = %r{\e\[\d+G\s+}m # Cursor Horizontal Absolute + white space
    BOJSON = %r{^[\[\{]} # Beginning Of JSON at start of string
    NEWLINES = %r{[\r\n]+}
    BYE = %r{^bye\n}m

    attr_reader :stdout

    def initialize(stdout = STDOUT)
      @stdout = stdout
      @output, @input, @pid = PTY.spawn(*CMD)
      @stdout.print read
    end

    def readpartial_rescued(size)
      begin
        @output.readpartial(size)
      rescue EOFError
        nil
      end
    end

    # read shell output up to and including the prompt
    #
    # @param [Regexp] prompt
    #
    # @return [String]
    def read(prompt = PROMPT)
      result = []
      begin
        buffer = readpartial_rescued(1024)
        result << buffer
      end until !buffer || buffer =~ prompt
      result.join
    end

    # write a line to the shell
    #
    # @param [String] line terminated with a newline
    # @param [Regexp] prompt
    #   Shell output is read up to and including the prompt
    #
    # @return [Mongo::Shell] self
    def write(line, prompt = PROMPT)
      @input.write(line)
      self
    end

    # put a string to the shell and add a newline
    #
    # @param [String] s without a newline
    # @param [Regexp] prompt
    #   Shell output is read up to and including the prompt
    #
    # @return [Mongo::Shell] self
    def puts(s, prompt = PROMPT)
      @input.puts(s)
      self
    end

    # execute a command and return the string output
    #
    # @param [String] s
    # @param [Regexp] prompt
    #   Shell output is read up to and including the prompt
    #
    # @return [String]
    def x(s, prompt = PROMPT) # as per Ruby built-in %x{...}
      puts(s, prompt).read
    end


    # execute a command and return the string results
    #
    # @param [String] s
    # @param [Regexp] prompt
    #   Shell output is read up to and including the prompt
    #
    # @return [Hash] JSON results in Ruby form
    def x_s(s, prompt = PROMPT) # as per Ruby built-in %x{...}
      result = puts(s, prompt).read.sub(PROMPT_EOS,'').split(CHA_S).last.chomp
      (result =~ BOJSON) ? result : result.split(NEWLINES).last
    end

    # execute a command and return the JSON results
    #
    # @param [String] s
    # @param [Regexp] prompt
    #   Shell output is read up to and including the prompt
    #
    # @raise [TypeError, JSON::ParserError]
    #
    # @return [Hash] JSON results in Ruby form
    def x_json(s, prompt = PROMPT) # as per Ruby built-in %x{...}
      begin
        JSON.parse x_s(s, prompt)
      rescue TypeError => e
        raise TypeError, e.message + s.inspect
      rescue JSON::ParserError => e
        raise JSON::ParserError, e.message + s.inspect
      end
    end

    # execute a command and return the Ruby results
    #
    # @param [String] s
    # @param [Regexp] prompt
    #   Shell output is read up to and including the prompt
    #
    # @return [Hash, String, nil] JSON, string results, or nil
    def x_ruby(s, prompt = PROMPT) # as per Ruby built-in %x{...}
      result = x_s(s, prompt)
      begin
        JSON.parse result
      rescue TypeError, JSON::ParserError
        result
      end
    end

    # execute a script and print the results
    #
    # @param [String] s
    # @param [Regexp] prompt
    #   Shel output is read up to and including the prompt
    def sh(s, prompt = PROMPT)
      prompt = BYE if s == 'exit'
      s.split("\n").each{|line| @stdout.print x(line, prompt)}
    end

    # exit the shell
    #
    # @return [Mongo::Shell] self
    def exit
      write("exit\n", BYE)
      self
    end

    # execute script to start a replica set test in the mongo shell
    #
    # @params [Hash] opts - name, nodes, startPort
    def replica_set_test_start(opts = { :name => 'test', :nodes => 3, :startPort => 31000 })
      STDOUT.flush
      sh <<-EOF
        var replTest = new ReplSetTest( #{opts.to_json} );
        var nodes = replTest.startSet();
        replTest.initiate();
        replTest.awaitReplication();
      EOF
    end

    # execute script to stop a replica set test in the mongo shell
    def replica_set_test_stop
      sh "replTest.stopSet();"
    end
  end
end

# this test class should be good for multiple tests that should be run against the same cluster
# use another file and test class for a different cluster configuration or logical grouping
class MongoShellTest < Test::Unit::TestCase

  class << self
    def startup
      @@mongo = Mongo::Shell.new(StringIO.new)
      @@opts = {:name => 'test', :nodes => 3, :startPort => 31000}
      @@mongo.replica_set_test_start(@@opts)
      @@client = Mongo::MongoReplicaSetClient.new(["localhost:#{@@opts[:startPort]}"], :name => @@opts[:name])
    end

    def shutdown
      @@client.close
      @@mongo.replica_set_test_stop
      @@mongo.sh "exit" # mongo.exit.read.out
      #print @@mongo.stdout.string # for debugging
    end
  end

  def setup
    assert @@client.connected?
  end

  def teardown

  end

  def argf_each # ARGF example - command arg files or stdin
    mongo = Mongo::Shell.new
    ARGF.each do |line|
      mongo.sh line
    end
    print mongo.sh "exit"
  end

  def test_shell_function_examples
    puts %Q(Ruby isMaster: #{@@client['admin'].command({:ismaster => 1}).inspect})
    puts "\nx examples ...\n\n"
    puts %Q(x_s isMaster: #{@@mongo.x_s("replTest.callIsMaster();").inspect})
    puts %Q(x_json nodeList: #{@@mongo.x_json("replTest.nodeList();").inspect})
    puts %Q(x_ruby getReplSetConfig: #{@@mongo.x_ruby("replTest.getReplSetConfig();").inspect})

    puts "\nReplSetTest function examples ...\n\n"
    %w( nodeList getReplSetConfig getURL callIsMaster getMaster getPrimary getSecondaries getSecondary status
        getLastOpTimeWritten ).each do |fn|
      puts %Q(#{fn}: #{@@mongo.x_ruby("replTest.#{fn}();")})
    end
    # Other ReplSetTest functions
    # initBridges initLiveNodes getNodeId getPort getPath getOptions startSet awaitRSClientHosts awaitSecondaryNodes
    # add remove initiate reInitiate awaitReplication getHashes start restart stopMaster stop stopSet waitForMaster
    # waitForHealth waitForState waitForIndicator overflow bridge partition unpartition
  end

  def test_aggregate_on_secondary
    db = @@client['test']
    coll = db['agg']
    coll.remove
    count = 3
    count.times{ coll.insert({}) }
    db.get_last_error({:w => 3})
    assert_equal(count, coll.aggregate([{'$group' => {:_id => nil, :count => {'$sum' => 1}}}]).first['count'], :read => :secondary)
  end

end


