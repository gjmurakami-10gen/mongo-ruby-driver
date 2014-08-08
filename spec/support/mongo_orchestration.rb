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
      attr_reader :uri, :object, :config, :method, :request, :response

      @@debug = false

      def debug
        @@debug
      end

      def debug=(value)
        @@debug = value
      end

      def initialize(uri = '', object = nil, config = nil)
        @uri = uri
        @object = object
        @config = config
      end

      def http_request(method, path = nil)
        @method = method
        @request = [@uri, path].compact.join('/')
        #puts "#{@method.upcase: #{@request}" if debug
        @response = self.class.send(method, @request)
        puts result_message if debug
        self
      end

      def post(path = nil, post_data)
        @method = __method__
        @request = [@uri, path].compact.join('/')
        #puts "#{__method__} request: #{@request.inspect} post_data: #{post_data.inspect}" if debug
        @response = self.class.post(@request, {body: post_data.to_json})
        puts result_message if debug
        self
      end

      def get(path = nil)
        http_request(__method__, path)
      end

      def put(path = nil)
        http_request(__method__, path)
      end

      def delete(path = nil)
        http_request(__method__, path)
      end

      def humanized_http_response_class_name
        @response.response.class.name.split('::').last.sub(/^HTTP/, '').gsub(/([a-z\d])([A-Z])/, '\1 \2')
      end

      def result_message
        msg = "#{@method.upcase} #{@request}, #{@response.code} #{humanized_http_response_class_name}"
        msg += ", post data: #{@post_data.inspect}" if @method == :post
        return msg if @response['content-length'] == "0"
        if @response.headers['content-type'].include?('application/json')
          msg += ", response JSON:\n#{JSON.pretty_generate(@response)}"
        else
          msg += ", response: #{@response.inspect}"
        end
      end

    end

    class Service < Base; end
    class Cluster < Base; end
    class Hosts < Cluster; end
    class RS < Cluster; end
    class SH < Cluster; end
    class Host < Base; end

    class Service
      VERSION_REQUIRED = "0.9"
      ORCHESTRATION_CLASS = { 'hosts' => Hosts, 'rs' => RS, 'sh' => SH }

      def initialize(uri = '')
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

      def configure(config)
        orchestration = config[:orchestration]
        uri = [@uri, orchestration].join('/')
        ORCHESTRATION_CLASS[orchestration].new(uri, nil, config)
      end
    end

    class Host
      def initialize(uri = '', object = nil)
        super
      end

      def status
        get
        @object = @response.parsed_response if @response.code == 200
        self
      end

      def start
        put(:start)
        if @response.code == 200
          @object = @response.parsed_response
        else
          raise "#{self.class.name}##{__method__} #{result_message}"
        end
        self
      end

      def stop
        put(:stop)
        self
      end

      def restart
        put(:restart)
        if @response.code == 200
          @object = @response.parsed_response
        else
          raise "#{self.class.name}##{__method__} #{result_message}"
        end
        self
      end
    end

    class Cluster
      def initialize(uri = '', object = nil, config = nil)
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
          post(nil, @post_data)
          if @response.code == 200
            @object = @response.parsed_response
          else
            raise "#{self.class.name}##{__method__} #{result_message}"
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
          raise "#{self.class.name}##{__method__} #{result_message}" unless @response.code == 204
          #@object = nil
        end
        self
      end

    end

    class Hosts
      def initialize(uri = '', object = nil, config = nil)
        super
      end

      def host
        uri = [@uri, @object['id']].join('/')
        Host.new(uri, @object)
      end
    end

    class RS
      def initialize(uri = '', object = nil, config = nil)
        super
      end
    end

    class SH
      def initialize(uri = '', object = nil, config = nil)
        super
      end
    end
  end
end
