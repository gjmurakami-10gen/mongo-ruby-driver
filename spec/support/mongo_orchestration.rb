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
require 'pp'

module Mongo
  module Orchestration

    class Base
      include HTTParty

      DEFAULT_BASE_URI = 'http://localhost:8889'
      base_uri (ENV['MONGO_ORCHESTRATION'] || DEFAULT_BASE_URI)
      attr_reader :base_path, :method, :abs_path, :response

      @@debug = false

      def debug
        @@debug
      end

      def debug=(value)
        @@debug = value
      end

      def initialize(base_path = '')
        @base_path = base_path
      end

      def http_request(method, path = nil, options = {})
        @method = method
        @abs_path = [@base_path, path].compact.join('/')
        @options = options
        @options[:body] = @options[:body].to_json if @options.has_key?(:body)
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

      def ok
        (@response.code/100) == 2
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

    class Resource < Base
      attr_reader :request_content, :object

      def initialize(base_path = '', request_content = nil)
        super(base_path)
        @request_content = request_content
        get
      end

      def get
        super
        @object = @response.parsed_response if ok
        self
      end

      def sub_resource(sub_class, path)
        sub_class.new([@base_path, path].join('/'))
      end
    end

    class Service < Resource
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

    class Host < Resource
      def status
        get
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
        raise "#{self.class.name}##{method} #{message_summary}" unless ok
        self
      end
    end

    class Cluster < Resource
      def status
        get
      end

      def start
        unless status.ok
          put(nil, {body: @request_content})
          if ok
            @object = @response.parsed_response
          else
            raise "#{self.class.name}##{__method__} #{message_summary}"
          end
        end
        self
      end

      def stop
        if status.ok
          delete
          raise "#{self.class.name}##{__method__} #{message_summary}" unless @response.code == 204
          #@object = nil
        end
        self
      end

    private
      def component(klass, path, object, id_key)
        base_path = ((path =~ %r{^/}) ? '' : "#{@base_path}/") + "#{path}/#{object[id_key]}"
        klass.new(base_path)
      end

      def components(get_resource, klass, resource, id_key)
        sub_rsrc = sub_resource(Resource, get_resource)
        hosts_data = sub_rsrc.ok ? sub_rsrc.object : []
        [hosts_data].flatten(1).collect{|host_data| component(klass, resource, host_data, id_key)}
      end
    end

    class Hosts < Cluster
      def host
        Host.new(['/hosts', @object['id']].join('/'))
      end
    end

    class RS < Cluster
      def members
        components('members', Host, '/hosts', 'host_id');
      end

      def primary
        sub_rsrc = sub_resource(Resource, 'primary')
        return sub_rsrc.ok ? component(Host, '/hosts', sub_rsrc.object, 'host_id') : nil
      end

      def secondaries
        components('secondaries', Host, '/hosts', 'host_id');
      end

      def arbiters
        components('arbiters', Host, '/hosts', 'host_id');
      end

      def hidden
        components('hidden', Host, '/hosts', 'host_id');
      end
    end

    class SH < Cluster
      def shards
        members = sub_resource(Resource, 'members')
        members.ok ? members.object.collect{|member| shard(member)} : []
      end

      def members
        components(__method__, Resource, 'members', 'id')
      end

      def configservers # JSON configuration response uses configsvrs # TODO - unify configservers / configsvrs
        components(__method__, Host, '/hosts', 'id')
      end

      def routers
        components(__method__, Host, '/hosts', 'id')
      end

    private
      def shard(object)
        return RS.new("/rs/#{object['_id']}") if object.has_key?('isReplicaSet')
        return Hosts.new("/hosts/#{object['_id']}") if object.has_key?('isHost')
        nil
      end
    end

    class Service
      ORCHESTRATION_CLASS = { 'hosts' => Hosts, 'rs' => RS, 'sh' => SH }

      def configure(config)
        orchestration = config[:orchestration]
        request_content = config[:request_content]
        klass = ORCHESTRATION_CLASS[orchestration]
        id = request_content[:id]
        unless id
          http_request = Base.new.post(orchestration, {:body => request_content})
          id = http_request.response.parsed_response.id
        end
        base_path = [@base_path, orchestration, id].join('/')
        cluster = klass.new(base_path, request_content)
        cluster.start
      end
    end
  end
end
