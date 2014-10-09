$SPEC_DIR = File.absolute_path(File.join(File.dirname(__FILE__), '..', 'spec'))
$LOAD_PATH.unshift($SPEC_DIR)
$LIB_DIR = File.absolute_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift($LIB_DIR)

require 'support/mongo_orchestration'
require 'mongo'
require 'support/monitoring'
require 'pp'

module Mongo
  class Client
    def create_from_uri(connection_string, options = {})
      uri = URI.new(connection_string)
      @options = options.merge(uri.client_options).freeze
      @cluster = Cluster.new(self, uri.servers, @options)
      @database = Database.new(self, @options[:database])
    end
  end
  class Cluster
    def initialize(client, addresses, options = {})
      @client = client
      @addresses = addresses
      @options = options.freeze
      @mode = Mode.get(options)
      @servers = addresses.map do |address|
        Server.new(address, options).tap do |server|
          unless @mode == Mongo::Cluster::Mode::Standalone
            subscribe_to(server, Event::SERVER_ADDED, Event::ServerAdded.new(self))
            subscribe_to(server, Event::SERVER_REMOVED, Event::ServerRemoved.new(self))
          end
        end
      end
    end
    def scan!
      @servers.each do |server|
        begin
          server.check!
        rescue Exception => e
          p [self.class,__method__,__FILE__,__LINE__]
          p e
          raise e
        end
      end
    end
    module Mode
      class Standalone
        def self.servers(servers, name = nil)
          raise "#{self.name}.#{__method__}: only one server expected, servers: #{servers.inspect}" if servers.size != 1
          servers
        end
      end
    end
  end
  class Server
    class Monitor
      def ismaster
        start = Time.now
        begin
          result = connection.dispatch([ ISMASTER ]).documents[0]
          return result, calculate_round_trip_time(start)
        rescue Mongo::SocketError, Errno::ECONNREFUSED, SystemCallError, IOError => e
          connection.disconnect!
          return {}, calculate_round_trip_time(start)
        rescue Exception => e
          log(:debug, 'MONGODB', [ "ismaster - unexpected exception #{e} #{e.message}" ])
          raise e
        end
      end
    end
  end
end

mo ||= Mongo::Orchestration::Service.new
configuration = {
    orchestration: 'replica_sets',
    request_content: {
        id: 'replica_sets_arbiter',
        preset: 'arbiter.json'
    }
}
topology = mo.configure(configuration)
topology.reset
mongodb_uri = topology.object['mongodb_uri'].sub(%r{/\?}, "/test?")
p mongodb_uri

begin
  client = Mongo::Client.new(mongodb_uri)
  pp client.cluster
  client.cluster.scan!
  pp client.command({dbStats: 1})
rescue Exception => e
  p e
  # #<NoMethodError: undefined method `context' for nil:NilClass>
  pp e.backtrace
  # ["/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/collection.rb:177:in `insert_many'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/collection.rb:156:in `insert_one'",
  #  "ruby-820-cluster-next-primary.rb:70:in `<main>'"]
end

topology.destroy
