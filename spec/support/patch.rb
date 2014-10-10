$reroute = true

# RUBY-814 - RUBY-830 - 17 issues filed so far

module Mongo
  class Client

    # RUBY-816 - client options lost when creating with URI
    # RUBY-822 - replica set created from URI does not instantiate cluster mode for replica set
    def initialize(addresses_or_uri, options = {})
      if addresses_or_uri.is_a?(::String)
        create_from_uri(addresses_or_uri, options)
      else
        create_from_addresses(addresses_or_uri, options)
      end
    end

    private

    # nit - use @options for consistency with create_from_uri
    def create_from_addresses(addresses, options = {})
      @options = options.freeze
      @cluster = Cluster.new(self, addresses, @options)
      @database = Database.new(self, @options[:database])
    end

    # RUBY-815 - replica set uri sets wrong cluster mode
    def create_from_uri(connection_string, options = {})
      uri = URI.new(connection_string)
      @options = options.merge(uri.client_options).freeze
      @cluster = Cluster.new(self, uri.servers, @options)
      @database = Database.new(self, @options[:database])
    end

  end

  class NoMaster < MongoError; end

  class Cluster

    # RUBY-818 - standalone server removed from cluster and not added back
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

    # RUBY-820 - cluster next_primary method returns nil with empty standalone config
    def next_primary
      if client.cluster.mode == Mongo::Cluster::Mode::ReplicaSet
        primary = client.server_preference.primary(servers).first
      else
        primary = servers.first
      end
      raise Mongo::NoMaster.new("no master") unless primary
      primary
    end

    # hack to add servers for code that is not sensitive to client mode
    def scan!
      if @servers.empty?
        @servers = @addresses.map do |address|
          Server.new(address, @options).tap do |server|
            unless mode == Mongo::Cluster::Mode::Standalone
              subscribe_to(server, Event::SERVER_ADDED, Event::ServerAdded.new(self))
              subscribe_to(server, Event::SERVER_REMOVED, Event::ServerRemoved.new(self))
            end
          end
        end
      end
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

    # RUBY-817 - servers removed from cluster and not added back
    def remove(address)
      removed_servers = @servers.reject!{ |server| server.address.seed == address }
      removed_servers.each{ |server| server.disconnect! } if removed_servers
      #addresses.reject!{ |addr| addr == address }
    end

    module Mode
      class Standalone

        # RUBY-819 - cluster mode standalone servers erroneously returns array containing nil
        def self.servers(servers, name = nil)
          raise "#{self.name}.#{__method__}: only one server expected, servers: #{servers.inspect}" if servers.size != 1
          servers
        end

      end
    end
  end

  class Server
    class Monitor

      # RUBY-821 - server monitor ismaster method fails to disconnect and fails to rescue all relevant errors
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

    class Description
      module Inspection
        class ServerRemoved

          # no bug - but may want to remove server if it is correctly added by discovery that is mode sensitive
          def self.run(description, updated)
            if updated.config.empty?
              # currently there's an issue with removing a server here
              #description.server.publish(Event::SERVER_REMOVED, updated.server.address.seed)
            end
            description.hosts.each do |host|
              if updated.primary? && !updated.hosts.include?(host)
                description.server.publish(Event::SERVER_REMOVED, host)
              end
            end
          end

        end
      end
    end

    def ping_time
      return 0.001
    end
  end

  class NoReadPreference < MongoError; end

  class Database

    # RUBY-823 - Database#command method lacks options for read preference and tags
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

  class Collection
    class View

      module Iterable

        # RUBY-824 - disconnect! when an error occurs in Collection::View::Iterable#each
        # RUBY-830 - Retries for a query
        # client mode sensitive and behavior for retries and disconnect on error
        def each
          tries = 0
          begin
            if client.cluster.mode == Mongo::Cluster::Mode::ReplicaSet
              server = read.select_servers(cluster.servers).first
            else
              server = cluster.servers.first
            end
            raise Mongo::NoReadPreference.new("No replica set member available for query with read preference matching mode #{read.name.to_s}") unless server
            cursor = Cursor.new(view, send_initial_query(server), server).to_enum
            cursor.each do |doc|
              yield doc
            end if block_given?
            cursor
          rescue Mongo::NoMaster, Mongo::NoReadPreference, Mongo::SocketError, Errno::ECONNREFUSED => e
            server.disconnect! if server
            tries += 1
            raise e if tries > 3
            sleep(2)
            collection.cluster.scan!
            retry
          rescue Exception => e
            p [self.class,__method__,__FILE__,__LINE__]
            p e
            raise e
          end
        end

        # RUBY-829 - enumerable cursor with next method
        # no bug - attempt to provide an enumerable for individual calls to #next
        def cursor
          tries = 0
          begin
            server = read.select_servers(cluster.servers).first
            raise Mongo::NoReadPreference.new("No replica set member available for query with read preference matching mode #{read.name.to_s}") unless server
            Cursor.new(view, send_initial_query(server), server).to_enum
          rescue Mongo::NoMaster, Mongo::NoReadPreference, Mongo::SocketError, Errno::ECONNREFUSED => e
            server.disconnect! if server
            tries += 1
            raise e if tries > 3
            sleep(2)
            collection.cluster.scan!
            retry
          rescue Exception => e
            p [self.class,__method__,__FILE__,__LINE__]
            p e
            raise e
          end
        end

      end

      module Readable

        # no bug - convenience
        def get_one
          limit(1).to_a.first
        end

      end

    end
  end

  class Connection

    # RUBY-825 - disconnect! when a socket error occurs in Connection#dispatch
    def dispatch(messages)
      begin
        write(messages)
        messages.last.replyable? ? read : nil
      rescue Mongo::SocketError => e
        disconnect!
        raise e
      end
    end

  end

  module Event
    class ServerAdded
      include Loggable

      # RUBY-826 - log adding a server to the cluster
      # log message added to be symmetric with ServerRemoved
      def handle(address)
        log(:debug, 'MONGODB', [ "#{address} being added to the cluster." ])
        cluster.add(address)
      end

    end
  end

  module Operation
    class Command

      # RUBY-827 - standalone client should not reroute
      # global $reroute is just a hack to bypass rerouting for a client with mode standalone
      def execute(context)
        # @todo: Should we respect tag sets and options here?
        if $reroute
          if context.server.secondary? && !secondary_ok?
            warn "Database command '#{selector.keys.first}' rerouted to primary server"
            context = Mongo::ServerPreference.get(:mode => :primary).server.context
          end
        end
        execute_message(context)
      end
    end

    # RUBY-828 - Operation::Executable#execute raises exception for mongos
    # added context.mongos?
    module Executable
      def execute(context)
        unless context.primary? || context.standalone? || context.mongos? || secondary_ok?
          raise Exception, "Must use primary server"
        end
        context.with_connection do |connection|
          connection.dispatch([ message ])
        end
      end
    end
  end

end
