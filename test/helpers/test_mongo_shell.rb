require 'test_helper'
require 'pp'
require 'json'

class String
  def pretrim_lines
    gsub(/^\s+/, '')
  end

  def parse_psuedo_array
    self[/^\[(.*)\]$/m,1].split(',').collect{|s| s.strip}
  end

  def sub_to_json_start
    sub(/^[^{]*{/m, '{')
  end

  def gsub_isodate
    gsub(/ISODate\((".+?")\)/, '\1')
  end

  def gsub_timestamp
    gsub(/Timestamp\((\d+), \d+\)/, '\1')
  end

  def to_json
    sub_to_json_start.gsub_isodate.gsub_timestamp
  end
end

# Mongo::Shell should be extracted into a separate file but is left here for the purposes of demonstration for now
module Mongo
  # A Mongo shell for cluster testing with methods for socket communication and testing convenience.
  # IO is synchronous with delimiters such as the prompt "> ".
  class Shell

    class Node
      attr_reader :rs, :conn, :host_port, :host, :port

      def initialize(rs, conn)
        @rs = rs
        @conn = conn
        @host_port = conn.sub('connection to ', '')
        @host_port = host_port
        @host, @port = host_port.split(':')
        @port = @port.to_i
      end

      def self.a_from_list(rs, list)
        list.collect{|s| Node.new(rs, s)}
      end

      def id
        @rs.x_s("rs.getNodeId(#{@conn.inspect});").to_i
      end

      def kill(signal = Signal.list['KILL'])
        result = @rs.x_s("rs.stop(#{id.inspect},#{signal.inspect});")
        raise result unless /shell: stopped mongo program/.match(result)
      end

      def stop
        result = @rs.x_s("rs.stop(#{id.inspect});")
        raise result unless /shell: stopped mongo program/.match(result)
      end
    end

    MONGO = '../mongo/mongo'
    CMD = %W{#{MONGO} --nodb --shell --listen}
    PORT = 30001
    MONGO_TEST_FRAMEWORK_JS = 'test/tools/cluster_test.js'
    MONGO_LOG = ['mongo_shell.log', 'w']
    DEFAULT_OPTS = {:port => PORT, :out => STDOUT, :mongo_out => MONGO_LOG, :mongo_err => MONGO_LOG}
    RETRIES = 10
    PROMPT = %r{> $}m
    BYE = %r{^bye\n$}m

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
        cmd = CMD << @opts[:port].to_s << MONGO_TEST_FRAMEWORK_JS
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

    public

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

    def x(s, prompt = PROMPT)
      puts(s).read(prompt)
    end

    def x_s(s, prompt = PROMPT)
      puts(s).read(prompt).sub(prompt,'').chomp
    end

    def x_json(s, prompt = PROMPT)
      JSON.parse(x_s(s, prompt).to_json)
    end

    def sh(s, out = @out)
      s.split("\n").each{|line| line += "\n"; out.write(line); out.flush; out.write x(line); out.flush}
    end

    def replica_set_test_start(opts = { :name => 'test', :nodes => 3, :startPort => 31000 })
      sio = StringIO.new
      sh("var rs = new ReplSetTest( #{opts.to_json} );", sio)
      sh("rs.startSet();", sio)
      raise sio.string unless /ReplSetTest Starting/.match(sio.string)
      sh("rs.initiate();", sio)
      raise sio.string unless /Config now saved locally.  Should come online in about a minute./.match(sio.string)
      sh("rs.awaitReplication();", sio)
      raise sio.string unless /ReplSetTest awaitReplication: finished: all/.match(sio.string)
      sio.string
    end

    def replica_set_test_stop
      sio = StringIO.new
      sh("rs.stopSet();", sio)
      raise sio.string unless /ReplSetTest stopSet \*\*\* Shut down repl set - test worked \*\*\*/.match(sio.string)
      sio.string
    end

    def replica_set_test_restart
      <<-EOF.pretrim_lines
        rs.reInitiate(60000);
        rs.awaitReplication();
      EOF
    end

    def status
      x_s("rs.status();")
    end

    def nodes
      Node.a_from_list(self, x_s("rs.nodes;").parse_psuedo_array)
    end

    def primary
      Node.new(self, x_s("rs.getPrimary();"))
    end

    def primary_name
      primary.host_port
    end

    def secondaries
      Node.a_from_list(self, x_s("rs.getSecondaries();").parse_psuedo_array)
    end

    def secondary_names
      secondaries.map(&:host_port)
    end

    def arbiters # dummy
      []
    end

    def arbiter_names
      arbiters.map(&:host_port)
    end

    def node_list
      x_json("rs.nodeList();")
    end

    def node_list_as_ary
      node_list.collect{|seed| a = seed.split(':'); [a[0], a[1].to_i]}
    end

    def repl_set_name
      x_s("rs.name;")
    end

    alias_method :repl_set_seeds, :node_list
    alias_method :repl_set_seeds_old, :node_list_as_ary
    alias_method :replicas, :nodes
    alias_method :servers, :nodes

    def repl_set_seeds_uri
      repl_set_seeds.join(',')
    end
  end
end

class Test::Unit::TestCase
  include Mongo
  include BSON

  def ensure_cluster(kind=nil, opts={})
    case kind
      when :rs
        default_opts = {:name => 'test', :nodes => 3, :startPort => 31000}
        opts = default_opts.merge(opts)
        unless defined? @@rs
          @@rs = Mongo::Shell.new
          #pp @@rs.socket.methods.sort
        end
        if @@rs.x_s("typeof rs;") == "object"
          #puts "@@rs.status:\n"
          #puts @@rs.status
          @@rs.replica_set_test_start(opts)
        else
          @@rs.replica_set_test_start(opts)
        end
        @rs = @@rs
    end
  end

  def stop_cluster(kind=nil, opts={})
    case kind
      when :rs
        @@rs.replica_set_test_stop
    end
  end
end

Test::Unit.at_exit do
  TEST_BASE.class_eval { class_variable_get(:@@rs).exit }
end

