$SPEC_DIR = File.absolute_path(File.join(File.dirname(__FILE__), '..', 'spec'))
$LOAD_PATH.unshift($SPEC_DIR)
$LIB_DIR = File.absolute_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift($LIB_DIR)

require 'support/mongo_orchestration'
require 'mongo'

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
# "mongodb://localhost:1087,localhost:1088,localhost:1089/test?replicaSet=replica_sets_arbiter"
client = Mongo::Client.new(mongodb_uri)
p client.cluster.mode
# Mongo::Cluster::Mode::Standalone

topology.destroy
