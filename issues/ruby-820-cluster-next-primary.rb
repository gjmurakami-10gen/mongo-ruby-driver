$SPEC_DIR = File.absolute_path(File.join(File.dirname(__FILE__), '..', 'spec'))
$LOAD_PATH.unshift($SPEC_DIR)
$LIB_DIR = File.absolute_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift($LIB_DIR)

require 'support/mongo_orchestration'
require 'mongo'
require 'support/monitoring'
require 'pp'

module Mongo
  class Cluster
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
    orchestration: 'servers',
    request_content: {
        id: 'servers_basic',
        preset: 'basic.json'
    }
}
topology = mo.configure(configuration)
topology.reset
mongodb_uri = topology.object['mongodb_uri'] + '/test'

begin
  client = Mongo::Client.new(mongodb_uri)
  client.cluster.scan!
  topology.stop
  client.cluster.scan!
  client['test'].insert_one({a: 1})
rescue Exception => e
  p e
  # #<NoMethodError: undefined method `context' for nil:NilClass>
  pp e.backtrace
  # ["/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/collection.rb:177:in `insert_many'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/collection.rb:156:in `insert_one'",
  #  "ruby-820-cluster-next-primary.rb:70:in `<main>'"]
end

topology.destroy
