require 'spec_helper'

RSpec.configure do |c|
  begin
    mo = Mongo::Orchestration::Service.new
  rescue => ex
    c.filter_run_excluding :orchestration => true
  end
end

describe Mongo::Orchestration::Base, :orchestration => true do
  let(:base) { described_class.new }

  it 'provides http_request method' do
    base.http_request(:get)
    expect(base.response.code).to eq(200)
    expect(base.response.parsed_response['service']).to eq('mongo-orchestration')
  end

  it 'provides get method' do
    base.http_request(:get)
    expect(base.response.code).to eq(200)
    expect(base.response.parsed_response['service']).to eq('mongo-orchestration')
    expect(base.response.response.class.name).to eq("Net::HTTPOK")
    expect(base.humanized_http_response_class_name).to eq("OK")
    expect(base.result_message).to match(/^GET .* OK,.* JSON:/)
  end
end

standalone_config = {
    orchestration: "hosts",
    post_data: {
        id: "standalone",
        name: "mongod",
        procParams: {
            journal: true
        }
    }
}

describe Mongo::Orchestration::Service, :orchestration => true do
  let(:service) { described_class.new }
  let(:cluster) { service.configure(standalone_config) }

  it 'initializes and checks service' do
    expect(service.response.parsed_response['service']).to eq('mongo-orchestration')
  end

  it 'configures a cluster/host' do
    expect(cluster).to be_kind_of(Mongo::Orchestration::Cluster)
    expect(cluster).to be_instance_of(Mongo::Orchestration::Hosts)
  end
end

describe Mongo::Orchestration::Cluster, :orchestration => true do
  let(:service) { Mongo::Orchestration::Service.new }
  let(:cluster) { service.configure(standalone_config) }

  it 'runs start, status, and stop methods' do
    cluster.stop # assume stopped

    cluster.start
    expect(cluster.method).to eq(:post)
    expect(cluster.request).to eq('/hosts')
    expect(cluster.response.code).to eq(200)
    expect(cluster.object).to be
    expect(cluster.object['serverInfo']['ok']).to eq(1.0)

    cluster.start # start for already started
    expect(cluster.method).to eq(:get)
    expect(cluster.request).to eq('/hosts/standalone')
    expect(cluster.response.code).to eq(200)
    expect(cluster.object).to be
    expect(cluster.object['serverInfo']['ok']).to eq(1.0)

    cluster.status # status for started
    expect(cluster.method).to eq(:get)
    expect(cluster.request).to eq('/hosts/standalone')
    expect(cluster.response.code).to eq(200)
    expect(cluster.object).to be
    expect(cluster.object['serverInfo']['ok']).to eq(1.0)

    uri = cluster.object['uri']

    # add client connection when Ruby is ready for prime time

    cluster.stop
    expect(cluster.method).to eq(:delete)
    expect(cluster.response.code).to eq(204)

    cluster.stop # stop for already stopped
    expect(cluster.method).to eq(:get)
    expect(cluster.response.code).to eq(404)

    cluster.status # status for stopped
    expect(cluster.method).to eq(:get)
    expect(cluster.response.code).to eq(404)
  end
end

describe Mongo::Orchestration::Hosts, :orchestration => true do
  let(:service) { Mongo::Orchestration::Service.new }
  let(:cluster) { service.configure(standalone_config) }

  it 'provides host method object with status, start, stop, and restart methods' do
    cluster.start
    host = cluster.host
    expect(host).to be_instance_of(Mongo::Orchestration::Host)

    host.status
    expect(host.method).to eq(:get)
    expect(host.request).to eq('/hosts/standalone')
    expect(host.response.code).to eq(200)

    host.stop
    expect(host.method).to eq(:put)
    expect(host.request).to eq('/hosts/standalone/stop')
    expect(host.response.code).to eq(200)

    host.status # TODO - need status for no process
    expect(host.method).to eq(:get)
    expect(host.request).to eq('/hosts/standalone')
    expect(host.response.code).to eq(200)

    host.start
    expect(host.method).to eq(:put)
    expect(host.request).to eq('/hosts/standalone/start')
    expect(host.response.code).to eq(200)

    host.restart
    expect(host.method).to eq(:put)
    expect(host.request).to eq('/hosts/standalone/restart')
    expect(host.response.code).to eq(200)

    cluster.stop
  end
end

replicaset_config = {
    orchestration: "rs",
    post_data: {
        id: "repl0",
        members: [
            {
                procParams: {
                    nohttpinterface: true,
                    journal: true,
                    noprealloc: true,
                    nssize: 1,
                    oplogSize: 150,
                    smallfiles: true
                },
                rsParams: {
                    priority: 99
                }
            },
            {
                procParams: {
                    nohttpinterface: true,
                    journal: true,
                    noprealloc: true,
                    nssize: 1,
                    oplogSize: 150,
                    smallfiles: true
                },
                rsParams: {
                    priority: 1.1
                }
            },
            {
                procParams: {
                    nohttpinterface: true,
                    journal: true,
                    noprealloc: true,
                    nssize: 1,
                    oplogSize: 150,
                    smallfiles: true
                }
            }
        ]
    }
}

describe Mongo::Orchestration::RS, :orchestration => true do
  let(:cluster) { @cluster }

  before(:all) do
    @service = Mongo::Orchestration::Service.new
    @cluster = @service.configure(replicaset_config)
    @cluster.start
  end

  after(:all) do
    @cluster.stop
  end

  it 'provides primary' do
    primary = @cluster.primary
    expect(primary).to be_instance_of(Mongo::Orchestration::Host)
  end

  it 'provides secondaries, arbiters, and hidden member methods' do
    [
        [:secondaries, 2],
        [:arbiters, 0],
        [:hidden, 0]
    ].each do |method, size|
      hosts = @cluster.send(method)
      expect(hosts.size).to eq(size)
      hosts.each do |host|
        expect(host).to be_instance_of(Mongo::Orchestration::Host)
      end
    end
  end
end

sharded_configuration = {
    orchestration: "sh",
    post_data: {
        id: "shard_cluster_1",
        configsvrs: [
            {
            }
        ],
        members: [
            {
                id: "sh1",
                shardParams: {
                    procParams: {
                    }
                }
            },
            {
                id: "sh2",
                shardParams: {
                    procParams: {
                    }
                }
            }
        ],
        routers: [
            {
            },
            {
            }
        ]
    }
}

describe Mongo::Orchestration::SH, :orchestration => true do
  let(:cluster) { @cluster }

  before(:all) do
    @service = Mongo::Orchestration::Service.new
    @cluster = @service.configure(sharded_configuration)
    @cluster.start
  end

  after(:all) do
    @cluster.stop
  end

  it 'provides members' do
    hosts = @cluster.members
    expect(hosts.size).to eq(2)
    hosts.each do |host|
      expect(host).to be_instance_of(Mongo::Orchestration::Host)
    end
  end

  it 'provides configsvrs' do # TODO - unify configservers
    hosts = @cluster.configsvrs
    expect(hosts.size).to eq(1)
    hosts.each do |host|
      expect(host).to be_instance_of(Mongo::Orchestration::Host)
    end
  end

  it 'provides routers' do
    hosts = @cluster.routers
    expect(hosts.size).to eq(2)
    hosts.each do |host|
      expect(host).to be_instance_of(Mongo::Orchestration::Host)
    end
  end
end
