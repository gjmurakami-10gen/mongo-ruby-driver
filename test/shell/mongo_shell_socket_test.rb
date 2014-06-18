require 'test_helper'
require 'pp'
require 'json'

class String
  def pretrim_lines
    gsub(/^\s+/, '')
  end
end

# Mongo::Shell should be extracted into a separate file but is left here for the purposes of demonstration for now
module Mongo
  # A Mongo shell for cluster testing with methods for socket communication and testing convenience.
  # IO is synchronous with delimiters such as the prompt "> ".
  class Shell
    MONGO = '../mongo/mongo'
    CMD = %W{#{MONGO} --nodb --shell --listen}
    PORT = 30001
    MONGO_LOG = ['mongo_shell.log', 'w']
    DEFAULT_OPTS = {:port => PORT, :out => STDOUT, :mongo_out => MONGO_LOG, :mongo_err => MONGO_LOG}
    RETRIES = 10
    PROMPT = %r{> $}m
    BYE = %r{^bye\n$}m

    CHA_S = %r{\e\[\d+G\s+}m # Cursor Horizontal Absolute + white space
    BOJSON = %r{^[\[\{]} # Beginning Of JSON at start of string
    NEWLINES = %r{[\r\n]+}


    attr_reader :socket

    def initialize(opts = {})
      @opts = DEFAULT_OPTS.merge(opts)
      @out = @opts[:out]
      @pid = nil
      connect
      read # blocking read for prompt
    end

    # spawn a mongo shell
    #
    # @return [true, false] true if mongo shell process was spawned
    def spawn
      unless @pid
        cmd = CMD << @opts[:port].to_s
        opts = {}
        opts[:out] = @opts[:mongo_out] if @opts[:mongo_out]
        opts[:err] = @opts[:mongo_err] if @opts[:mongo_err]
        @pid = Process.spawn(*cmd, opts)
        return true
      end
      return false
    end

    # connect to the mongo shell, spawning one if needed
    #
    # @return [Mongo::Shell] self
    def connect
      @socket = nil
      ex = nil
      RETRIES.times do
        begin
          @socket = ::TCPSocket.new('localhost', @opts[:port]) # not Mongo::TCPSocket
          return self if @socket
        rescue => ex
          spawn || sleep(1)
        end
      end
      abort("Error on connect to mongo shell after #{RETRIES} retries: #{ex}")
    end

    # read shell output up to and including the prompt
    #
    # @param [Regexp] prompt
    #
    # @return [String]
    def read(prompt = PROMPT)
      result = []
      begin
        buffer = @socket.readpartial(1024)
        result << buffer
      end until !buffer || buffer =~ prompt
      result.join
    end

    def puts(s)
      s += "\n" if s[-1, 1] != "\n"
      @socket.print(s) # single write, not # @socket.puts(s) #
      self
    end

    # exit the mongo shell
    #
    # @return [Mongo::Shell] self
    def exit
      puts("exit").read(BYE)
      @socket.shutdown # graceful shutdown
      @socket.close
      Process.waitpid(@pid) if @pid
      self
    end

    def x(s, prompt = PROMPT) # as per Ruby built-in %x{...}
      puts(s).read(prompt)
    end

    def x_s(s, prompt = PROMPT) # as per Ruby built-in %x{...}
      result = puts(s).read(prompt).sub(prompt,'').chomp
      #(result =~ BOJSON) ? result : result.split(NEWLINES).last
    end

    def sh(s, out = @out)
      s.split("\n").each{|line| line += "\n"; out.write(line); out.flush; out.write x(line); out.flush}
    end

    def replica_set_test_start(opts = { :name => 'test', :nodes => 3, :startPort => 31000 })
      <<-EOF.pretrim_lines
        var replTest = new ReplSetTest( #{opts.to_json} );
        var nodes = replTest.startSet();
        replTest.initiate();
        replTest.awaitReplication();
      EOF
    end

    def replica_set_test_stop
      "replTest.stopSet();"
    end
  end
end

mongo = Mongo::Shell.new
#pp mongo.socket.methods.sort
opts = {:name => 'test', :nodes => 3, :startPort => 31000}
stringio = StringIO.new
mongo.sh(mongo.replica_set_test_start(opts), stringio)
print stringio.string
stringio.rewind
mongo.sh(mongo.replica_set_test_stop, stringio)
print stringio.string
mongo.exit

exit
