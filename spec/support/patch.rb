$debug = false # true #
$reroute = true

module Mongo
  class Client

    def initialize(addresses_or_uri, options = {})
      if addresses_or_uri.is_a?(::String)
        create_from_uri(addresses_or_uri, options)
      else
        create_from_addresses(addresses_or_uri, options)
      end
    end

    def server_preference(options = {})
      @server_preference = (options.empty? && @server_preference) || ServerPreference.get(options)
    end

    private

    def create_from_addresses(addresses, options = {})
      @cluster = Cluster.new(self, addresses, options)
      @options = options.freeze
      @database = Database.new(self, @options[:database])
    end

    def create_from_uri(connection_string, options = {})
      uri = URI.new(connection_string)
      @cluster = Cluster.new(self, uri.servers, options)
      @options = options.merge(uri.client_options).freeze
      @database = Database.new(self, @options[:database])
    end

  end

  class NoMaster < MongoError; end

  class Cluster

    def initialize(client, addresses, options = {})
      p [self.class,__method__,__FILE__,__LINE__] if $debug
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

    def next_primary
      primary = client.server_preference.primary(servers).first
      raise Mongo::NoMaster.new("no master") unless primary
      primary
    end

    def scan!
      p "***** #{self.class} *****" if $debug
      p [self.class,__method__,__FILE__,__LINE__] if $debug
      p "***** addresses:" if $debug
      p addresses if $debug
      p mode.name if $debug
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
      p @servers if $debug
      system("gps") if $debug
      @servers.each do |server|
        p [self.class,__method__,__FILE__,__LINE__] if $debug
        p server if $debug
        p server.description if $debug
        begin
          server.check!
        rescue Exception => e
          p [self.class,__method__,__FILE__,__LINE__]
          p e
          raise e
        end
      end
    end

    def remove(address)
      removed_servers = @servers.reject!{ |server| server.address.seed == address }
      removed_servers.each{ |server| server.disconnect! } if removed_servers
    end

    module Mode
      class Standalone

        def self.servers(servers, name = nil)
          p [self.name,__method__,__FILE__,__LINE__] if $debug
          p servers if $debug
          raise "#{self.name}.#{__method__}: only one server expected, servers: #{servers.inspect}" if servers.size != 1
          #servers.select{ |server| server.standalone? }
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
          pp result if $debug
          return result, calculate_round_trip_time(start)
        rescue Mongo::SocketError, Errno::ECONNREFUSED, SystemCallError, IOError => e
          p [self.class,__method__,__FILE__,__LINE__] if $debug
          connection.disconnect!
          #log(:debug, 'MONGODB', [ e.message ])
          return {}, calculate_round_trip_time(start)
        rescue Exception => e
          p [self.class,__method__,__FILE__,__LINE__]
          p "rescue Exception => e"
          p e
          raise e
        end
      end

    end

    class Description
      module Inspection
        class ServerRemoved

          def self.run(description, updated)
            p [self.name,__method__,__FILE__,__LINE__] if $debug
            if updated.config.empty?
              p "***** publish *****" if $debug
              p description if $debug
              p updated.server.address.seed if $debug
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

    def command(operation)
      p [self.class,__method__,__FILE__,__LINE__] if $debug
      p client.cluster.servers if $debug
      server = (client.cluster.mode == Mongo::Cluster::Mode::Standalone) ?
        cluster.servers.first :
        client.server_preference.select_servers(cluster.servers).first
      p client.server_preference if $debug
      p server if $debug
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

        def each
          tries = 0
          begin
            p [self.class,__method__,__FILE__,__LINE__] if $debug
            servers = cluster.servers
            p servers if $debug
            p read if $debug
            p read.select_servers(cluster.servers) if $debug
            server = read.select_servers(cluster.servers).first
            p server if $debug
            raise Mongo::NoReadPreference.new("No replica set member available for query with read preference matching mode #{read.name.to_s}") unless server
            cursor = Cursor.new(view, send_initial_query(server), server).to_enum
            cursor.each do |doc|
              yield doc
            end if block_given?
            cursor
          rescue Mongo::NoMaster, Mongo::NoReadPreference, Mongo::SocketError, Errno::ECONNREFUSED => e
            p [self.class,__method__,__FILE__,__LINE__] if $debug
            p e if $debug
            server.disconnect! if server
            tries += 1
            raise e if tries > 3
            sleep(2)
            system("gps") if $debug
            collection.cluster.scan!
            retry
          rescue Exception => e
            p [self.class,__method__,__FILE__,__LINE__]
            p e
            p "rescue Exception => e"
            raise e
          end
        end

      end

      module Readable

        def read(value = nil)
          return server_preference if value.nil?
          view = configure(:mode, value)
          server_preference(view.options)
          view
        end

        def get_one # convenience, no bug
          limit(1).to_a.first
        end

      end

    end
  end

  class Connection

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

      def handle(address)
        log(:debug, 'MONGODB', [ "#{address} being added to the cluster." ])
        cluster.add(address)
      end

    end
  end

  module Operation
    class Command
      def execute(context)
        p [self.class,__method__,__FILE__,__LINE__] if $debug
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
  end
end
