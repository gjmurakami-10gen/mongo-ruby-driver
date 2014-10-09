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
  # client.cluster.scan!
  # topology.stop
  # client.cluster.scan!
  client['test'].insert_one({a: 1})
rescue Exception => e
  p e
  # #<NoMethodError: undefined method `primary?' for nil:NilClass>
  pp e.backtrace
  # ["/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/server_preference/selectable.rb:82:in `block in primary'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/server_preference/selectable.rb:82:in `select'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/server_preference/selectable.rb:82:in `primary'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/cluster.rb:110:in `next_primary'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/collection.rb:177:in `insert_many'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/collection.rb:156:in `insert_one'",
  #  "next-primary.rb:24:in `<main>'"]
end

topology.destroy
