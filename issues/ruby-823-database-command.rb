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
    def initialize(addresses_or_uri, options = {})
      if addresses_or_uri.is_a?(::String)
        create_from_uri(addresses_or_uri, options)
      else
        create_from_addresses(addresses_or_uri, options)
      end
    end
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
  class Database
    def command(operation, options = {})
      server_preference = options[:read] ? ServerPreference.get(options[:read]) : client.server_preference
      server = server_preference.select_servers(cluster.servers).first
      raise Mongo::NoReadPreference.new("No replica set member available for query with read preference matching mode #{client.server_preference.name.to_s}") unless server
      Operation::Command.new({
        :selector => operation,
        :db_name => name,
        :options => { :limit => -1 }
      }).execute(server.context)
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

begin
  mongodb_uri = topology.object['mongodb_uri'].sub(%r{/\?}, "/test?")
  p mongodb_uri
  client = Mongo::Client.new(mongodb_uri, mode: :replica_set)
  pp client.cluster
  client.cluster.scan!
  pp client.command({dbStats: 1}, read: {mode: :primary})
  puts
  mongodb_uri_primary = topology.primary.object['mongodb_uri'] + "/test"
  p mongodb_uri_primary
  client = Mongo::Client.new(mongodb_uri_primary)
  pp client.cluster
  client.cluster.scan!
  pp client.command({dbStats: 1})
rescue Exception => e
  p e
  pp e.backtrace
end

topology.destroy
