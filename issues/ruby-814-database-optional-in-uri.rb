$SPEC_DIR = File.absolute_path(File.join(File.dirname(__FILE__), '..', 'spec'))
$LOAD_PATH.unshift($SPEC_DIR)
$LIB_DIR = File.absolute_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift($LIB_DIR)

require 'support/mongo_orchestration'
require 'mongo'
require 'pp'

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
mongodb_uri = topology.object['mongodb_uri']

p mongodb_uri
# "mongodb://localhost:27017"
begin
  Mongo::Client.new(mongodb_uri)
rescue Exception => e
  p e
  #<Mongo::Database::InvalidName: nil is an invalid database name. Please provide a string or symbol.>
  pp e.backtrace
  # ["/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/database.rb:151:in `initialize'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/client.rb:227:in `new'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/client.rb:227:in `create_from_uri'",
  #  "/Users/gjm/10gen/mongo-ruby-driver/lib/mongo/client.rb:116:in `initialize'",
  #  "ruby-814-database-optional-in-uri.rb:25:in `new'",
  #  "ruby-814-database-optional-in-uri.rb:25:in `<main>'"]
end

topology.destroy
