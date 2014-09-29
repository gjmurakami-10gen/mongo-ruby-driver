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

  class Cluster
    def scan!
      @servers.each do |server|
        p server
        begin
          server.check!
        rescue Mongo::SocketError => ex
        rescue Exception => ex
          p self.class
          p __method__
          p ex
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
p __method__
pp result
          return result, calculate_round_trip_time(start)
        rescue SystemCallError, IOError => e
          log(:debug, 'MONGODB', [ e.message ])
          return {}, calculate_round_trip_time(start)
        rescue Mongo::SocketError => e
          # p __method__
          # p e
          connection.disconnect!
          raise e
        end
      end
    end

    def ping_time
      return 0.001
    end
  end


  class Collection
    class View

      module Readable

        def read(value = nil)
          return server_preference if value.nil?
          view = configure(:mode, value)
          server_preference(view.options)
          view
        end

        def get_one
          limit(1).to_a.first
        end

      end

      private

      def send_initial_query(server)
        tries = 0
        begin
          initial_query_op.execute(server.context)
        rescue Mongo::SocketError, Errno::ECONNREFUSED => ex
p __method__
p ex
          server.disconnect!
          tries += 1
          raise ex if tries > 3
          sleep(2)
          retry
        end
      end

    end
  end

end
