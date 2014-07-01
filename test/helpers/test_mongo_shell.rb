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
  # Methods are for 1.x-stable compatibility but should be minimized for 2.x
  # Full documentation is pending.
  class Shell
    MONGO = '../mongo/mongo'
    CMD = %W{#{MONGO} --nodb --shell --listen}
    MONGO_PORT = 30001
    MONGO_TEST_FRAMEWORK_JS = 'test/tools/cluster_test.js'
    MONGO_LOG = ['mongo_shell.log', 'w']
    DEFAULT_OPTS = {:port => MONGO_PORT, :out => STDOUT, :mongo_out => MONGO_LOG, :mongo_err => MONGO_LOG}
    RETRIES = 10
    PROMPT = %r{> $}m
    BYE = %r{^bye\n$}m

    attr_reader :out, :socket

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
      raise("Error on connect to mongo shell after #{RETRIES} retries: #{ex}")
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
  end

  class ClusterTest
    VAR = 'ct'

    class Node
      attr_reader :cluster, :conn, :var, :host_port, :host, :port

      def initialize(cluster, conn)
        @cluster = cluster
        @conn = conn
        @var = @cluster.var
        @host_port = conn.sub('connection to ', '')
        @host_port = host_port
        @host, @port = host_port.split(':')
        @port = @port.to_i
      end

      def self.a_from_list(cluster, list)
        list.collect{|s| Mongo::ClusterTest::Node.new(cluster, s)}
      end

      def id
        @cluster.x_s("#{var}.getNodeId(#{@conn.inspect});").to_i
      end

      def kill(signal = Signal.list['KILL'])
        result = @cluster.x_s("#{var}.stop(#{id.inspect},#{signal.inspect},true);")
        raise result unless /shell: stopped mongo program/.match(result)
      end

      def stop
        result = @cluster.x_s("#{var}.stop(#{id.inspect},true);")
        raise result unless /shell: stopped mongo program/.match(result)
      end
    end

    attr_reader :var

    def initialize(ms, var = VAR)
      @ms = ms
      @var = var
    end

    def x_s(s, prompt = Mongo::Shell::PROMPT)
      @ms.x_s(s, prompt)
    end

    def x_json(s, prompt = Mongo::Shell::PROMPT)
      @ms.x_json(s, prompt)
    end

    def sh(s, out = @ms.out)
      @ms.sh(s, out)
    end

    def exists?
      x_s("typeof #{var};") == "object"
    end
  end

  class ReplSetTest <  ClusterTest
    VAR = 'rs'
    DEFAULT_OPTS = {
        :name => 'test',
        :nodes => 3,
        :startPort => 31000,
        :dataPath => "#{Dir.getwd}/data/" # must be a full path
    }

    def initialize(ms, var = VAR)
      @ms = ms
      @var = var
    end

    def start(opts = {})
      opts = DEFAULT_OPTS.dup.merge(opts)
      sio = StringIO.new
      sh("var #{var} = new ReplSetTest( #{opts.to_json} );", sio)
      sh("#{var}.startSet();", sio)
      raise sio.string unless /ReplSetTest Starting/.match(sio.string)
      sh("#{var}.initiate();", sio)
      raise sio.string unless /Config now saved locally.  Should come online in about a minute./.match(sio.string)
      sh("#{var}.awaitReplication();", sio)
      raise sio.string unless /ReplSetTest awaitReplication: finished: all/.match(sio.string)
      sio.string
    end

    def stop(cleanup = true)
      sio = StringIO.new
      sh("#{var}.stopSet(undefined, #{!cleanup});", sio)
      raise sio.string unless /ReplSetTest stopSet \*\*\* Shut down repl set - test worked \*\*\*/.match(sio.string)
      sio.string
    end

    def restart
      sio = StringIO.new
      sh("#{var}.restartSet();", sio)
      sh("#{var}.awaitSecondaryNodes(30000);", sio)
      sh("#{var}.awaitReplication(30000);", sio)
      raise sio.string unless /ReplSetTest awaitReplication: finished: all/.match(sio.string)
      sio.string
    end

    def status
      x_s("#{var}.status();")
    end

    def nodes
      Mongo::ClusterTest::Node.a_from_list(self, x_s("#{var}.nodes;").parse_psuedo_array)
    end

    def primary
      Mongo::ClusterTest::Node.new(self, x_s("#{var}.getPrimary();"))
    end

    def primary_name
      primary.host_port
    end

    def secondaries
      Mongo::ClusterTest::Node.a_from_list(self, x_s("#{var}.getSecondaries();").parse_psuedo_array)
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
      x_json("#{var}.nodeList();")
    end

    def node_list_as_ary
      node_list.collect{|seed| a = seed.split(':'); [a[0], a[1].to_i]}
    end

    def repl_set_name
      x_s("#{var}.name;")
    end

    alias_method :repl_set_seeds, :node_list
    alias_method :repl_set_seeds_old, :node_list_as_ary
    alias_method :replicas, :nodes
    alias_method :servers, :nodes

    def repl_set_seeds_uri
      repl_set_seeds.join(',')
    end

    def config
      result = x_json("#{var}.getReplSetConfig()")
      result['host'] = result['members'].first['host'].split(':').first
      result
    end

    def member_by_name(host_port)
      nodes.find{|node| node.host_port == host_port}
    end

    def stop_secondary
      secondaries.sample.stop
    end
  end

  class ShardingTest < ClusterTest
    VAR = 'sc'
    DEFAULT_OPTS = {
        :name => "test",
        :shards => 2,
        :rs => { :nodes => 3 },
        :mongos => 2,
        :other => { :separateConfig => true },
        :dataPath => "#{Dir.getwd}/data/" # must be a full path
    }

    def initialize(ms, var = VAR)
      @ms = ms
      @var = var
    end

    def start(opts = {})
      opts = DEFAULT_OPTS.dup.merge(opts)
      sio = StringIO.new
      sh("var #{var} = new ShardingTest( #{opts.to_json} );", sio)
      sio.string
    end

    def stop
      sio = StringIO.new
      sh("#{var}.stop();", sio)
      raise sio.string unless /\*\*\* ShardingTest test completed /.match(sio.string)
      sio.string
    end

    def restart
      sio = StringIO.new
      sh("#{var}.restart();", sio)
      sio.string
    end

    def s
      Mongo::ClusterTest::Node.new(self, x_s("#{var}.s;"))
    end

    def s0
      Mongo::ClusterTest::Node.new(self, x_s("#{var}.s0;"))
    end

    def s1
      Mongo::ClusterTest::Node.new(self, x_s("#{var}.s1;"))
    end

    def s2
      Mongo::ClusterTest::Node.new(self, x_s("#{var}.s2;"))
    end

    def config0
      Mongo::ClusterTest::Node.new(self, x_s("#{var}.config0;"))
    end

    def servers(type)
      case type
        when :routers
          [s0, s1, s2].select{|node| node.host}
      end
    end
    def mongos_seeds
      servers(:routers).map(&:host_port)
    end
  end
end

class Test::Unit::TestCase
  include Mongo
  include BSON

  def ensure_cluster(kind=nil, opts={})
    unless defined? @@ms
      @@ms = Mongo::Shell.new
    end
    case kind
      when :rs
        unless defined? @@rs
          @@rs = Mongo::ReplSetTest.new(@@ms, 'rs')
        end
        if @@rs.exists?
          @@rs.restart
        else
          opts = Mongo::ReplSetTest::DEFAULT_OPTS.dup.merge(opts)
          FileUtils.mkdir_p(opts[:dataPath])
          @@rs.start(opts)
        end
        @rs = @@rs
      when :sc
        unless defined? @@sc
          @@sc = Mongo::ShardingTest.new(@@ms, 'sc')
        end
        if @@sc.exists?
          @@sc.restart
        else
          opts = Mongo::ShardingTest::DEFAULT_OPTS.dup.merge(opts)
          FileUtils.mkdir_p(opts[:dataPath])
          @@sc.start(opts)
        end
        @sc = @@sc
    end
  end
end

Test::Unit.at_exit do
  mongo_shutdown = ENV['MONGO_SHUTDOWN']
  if mongo_shutdown.nil? || !mongo_shutdown.match(/^(0|false|)$/i)
    TEST_BASE.class_eval do
      begin
        rs = class_variable_get(:@@rs)
        rs.stop
      rescue
      end
      begin
        sc = class_variable_get(:@@sc)
        sc.stop
      rescue
      end
      begin
        ms = class_variable_get(:@@ms)
        ms.exit
      rescue
      end
    end
  end
end

