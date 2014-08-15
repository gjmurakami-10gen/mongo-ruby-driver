# Copyright (C) 2009-2014 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'mongo'
require 'httparty'

module Mongo
  module Orchestration

    class Base
      include HTTParty

      DEFAULT_BASE_URI = 'http://localhost:8889'
      base_uri (ENV['MONGO_ORCHESTRATION'] || DEFAULT_BASE_URI)
      attr_reader :base_path, :object, :config, :method, :abs_path, :response

      @@debug = false

      def debug
        @@debug
      end

      def debug=(value)
        @@debug = value
      end

      def initialize(base_path = '', object = nil, config = nil)
        @base_path = base_path
        @object = object
        @config = config
      end

      def http_request(method, path = nil, options = {})
        @method = method
        @abs_path = [@base_path, path].compact.join('/')
        @options = options
        @response = self.class.send(@method, @abs_path, @options)
        puts message_summary if debug
        self
      end

      def post(path = nil, options)
        http_request(__method__, path, options)
      end

      def get(path = nil, options = {})
        http_request(__method__, path, options)
      end

      def put(path = nil, options = {})
        http_request(__method__, path, options)
      end

      def delete(path = nil, options = {})
        http_request(__method__, path, options)
      end

      def humanized_http_response_class_name
        @response.response.class.name.split('::').last.sub(/^HTTP/, '').gsub(/([a-z\d])([A-Z])/, '\1 \2')
      end

      def message_summary
        msg = "#{@method.upcase} #{@abs_path}, options: #{@options.inspect}"
        msg += ", #{@response.code} #{humanized_http_response_class_name}"
        return msg if @response.headers['content-length'] == "0" # not Fixnum 0
        if @response.headers['content-type'].include?('application/json')
          msg += ", response JSON:\n#{JSON.pretty_generate(@response)}"
        else
          msg += ", response: #{@response.inspect}"
        end
      end
    end

    class Service < Base
      VERSION_REQUIRED = "0.9"

      def initialize(base_path = '')
        super
        check_service
      end

      def check_service
        get
        raise "mongo-orchestration service #{base_uri.inspect} is not available. Please start it via 'python server.py start'" if @response.code == 404
        version = @response.parsed_response['version']
        raise "mongo-orchestration service version #{version.inspect} is insufficient, #{VERSION_REQUIRED} is required" if version < VERSION_REQUIRED
        self
      end
    end

    class Host < Base
      def initialize(base_path = '', object = nil)
        super
      end

      def status
        get
        @object = @response.parsed_response if @response.code == 200
        self
      end

      def start
        put_with_check(__method__)
      end

      def stop
        put_with_check(__method__)
      end

      def restart
        put_with_check(__method__)
      end

      def freeze
        put_with_check(__method__)
      end

    private
      def put_with_check(method)
        put(method)
        raise "#{self.class.name}##{method} #{message_summary}" unless @response.code == 200
        self
      end
    end

    class Cluster < Base
      def initialize(base_path = '', object = nil, config = nil)
        super
        @post_data = @config[:post_data]
        @id = @post_data[:id]
      end

      def status
        get(@id)
        @object = @response.parsed_response if @response.code == 200
        self
      end

      def start
        status
        if @response.code != 200
          post(nil, {body: @post_data.to_json})
          if @response.code == 200
            @object = @response.parsed_response
          else
            raise "#{self.class.name}##{__method__} #{message_summary}"
          end
        else
          #put(@id)
        end
        self
      end

      def stop
        status
        if @response.code == 200
          delete(@id)
          raise "#{self.class.name}##{__method__} #{message_summary}" unless @response.code == 204
          #@object = nil
        end
        self
      end

    private
      def host(resource, host_data, id_key)
        base_path = [@base_path, @id, resource, host_data[id_key]].join('/')
        Host.new(base_path, host_data)
      end

      def hosts(get_resource, resource, id_key)
        base_path = [@base_path, @id, get_resource].join('/')
        response = self.class.get(base_path)
        hosts_data = (response.code == 200) ? response.parsed_response : []
        [hosts_data].flatten(1).collect{|host_data| host(resource, host_data, id_key)}
      end
    end

    class Hosts < Cluster
      def initialize(base_path = '', object = nil, config = nil)
        super
      end

      def host
        base_path = [@base_path, @object['id']].join('/')
        Host.new(base_path, @object)
      end
    end

    class RS < Cluster
      def initialize(base_path = '', object = nil, config = nil)
        super
      end

      def members
        hosts('members', 'members', '_id'); # host_id
      end

      def primary
        #hosts('primary', 'members', '_id').first
        base_path = [@base_path, @id, 'primary'].join('/')
        response = self.class.get(base_path)
        return (response.code == 200) ? Host.new(base_path, response.parsed_response) : nil
      end

      def secondaries
        hosts('secondaries', 'members', '_id'); # 'hosts', 'host_id'
      end

      def arbiters
        hosts('arbiters', 'members', '_id'); # 'hosts', 'host_id'
      end

      def hidden
        hosts('hidden', 'members', '_id'); # 'hosts', 'host_id'
      end
    end

    class SH < Cluster
      def initialize(base_path = '', object = nil, config = nil)
        super
      end

      def members
        hosts(__method__, 'members', 'id')
      end

      def configservers # JSON configuration response uses configsvrs # TODO - unify configservers / configsvrs
        hosts(__method__, 'members', 'id') # 'hosts', 'host_id'
      end

      def routers
        hosts(__method__, 'members', 'id') # 'hosts', 'host_id'
      end
    end

    class Service
      ORCHESTRATION_CLASS = { 'hosts' => Hosts, 'rs' => RS, 'sh' => SH }

      def configure(config)
        orchestration = config[:orchestration]
        base_path = [@base_path, orchestration].join('/')
        ORCHESTRATION_CLASS[orchestration].new(base_path, nil, config)
      end
    end
  end
end
