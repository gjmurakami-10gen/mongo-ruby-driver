# Copyright (C) 2009-2013 MongoDB, Inc.
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

require 'test_helper'
#require 'shell/test_shell'

class ClusterReplicaSetTest < Test::Unit::TestCase

  def setup
    ensure_cluster(:rs)
  end

  def test_rs_methods
    if defined? Mongo::Shell
      puts "@rs.nodes:#{@rs.nodes.inspect}"
      assert_equal([31000, 31001, 31002], @rs.nodes.map(&:port))
      puts "@rs.node_list:#{@rs.node_list.inspect}"
      assert_equal(3, @rs.node_list.size)
      puts "@rs.node_list_as_ary:#{@rs.node_list_as_ary.inspect}"
      assert_equal([31000, 31001, 31002], @rs.node_list_as_ary.map{|ary| ary.last})
      puts "@rs.primary.id:#{@rs.primary.id.inspect}"
      assert_equal(0, @rs.primary.id)
    end

    puts "@rs.primary:#{@rs.primary.inspect}"
    assert(@rs.primary.host_port.bytes.last != 34)
    assert(/:/.match(@rs.servers.first.host_port))
    puts "@rs.primary_name:#{@rs.primary_name.inspect}"
    assert_equal(String, @rs.primary_name.class)
    puts "@rs.secondaries:#{@rs.secondaries.inspect}"
    assert_equal(2, @rs.secondaries.size)
    puts "@rs.secondary_names:#{@rs.secondary_names.inspect}"
    assert_equal(2, @rs.secondary_names.size)
    puts "@rs.arbiters:#{@rs.arbiters.inspect}"
    assert_equal([], @rs.arbiters)
    puts "@rs.arbiter_names:#{@rs.arbiter_names.inspect}"
    assert_equal([], @rs.arbiter_names)
    puts "@rs.repl_set_name:#{@rs.repl_set_name.inspect}"
    assert_equal("test", @rs.repl_set_name)

    puts "@rs.repl_set_seeds:#{@rs.repl_set_seeds.inspect}"
    assert_equal(3, @rs.repl_set_seeds.size)
    puts "@rs.repl_set_seeds_old:#{@rs.repl_set_seeds_old.inspect}"
    assert_equal([31000, 31001, 31002], @rs.repl_set_seeds_old.map{|ary| ary.last})
    puts "@rs.repl_set_seeds_uri:#{@rs.repl_set_seeds_uri.inspect}"
    assert_equal(String, @rs.repl_set_seeds_uri.class)

    puts "@rs.servers:#{@rs.servers.inspect}"
    assert_equal([31000, 31001, 31002], @rs.servers.map(&:port))
    puts "@rs.servers.first.host:#{@rs.servers.first.host.inspect}"
    assert_equal(String, @rs.servers.first.host.class)
    puts "@rs.servers.first.port:#{@rs.servers.first.port.inspect}"
    assert_equal(31000, @rs.servers.first.port)
    puts "@rs.servers.first.host_port:#{@rs.servers.first.host_port.inspect}"
    assert(/:/.match(@rs.servers.first.host_port))

    puts "@rs.replicas:#{@rs.replicas.inspect}"
    assert_equal([31000, 31001, 31002], @rs.replicas.map(&:port))
  end

  def test_rs_restart
    sio = StringIO.new
    system("pgrep -fl mongo")
    assert_equal(["PRIMARY", "SECONDARY", "SECONDARY"], @rs.status["members"].map{|member| member["stateStr"]}.sort)
    puts "******** @rs.primary.stop ********"
    id = @rs.primary.stop
    system("pgrep -fl mongo")
    p @rs.status
    @@rs.restart
    system("pgrep -fl mongo")
    assert_equal(["PRIMARY", "SECONDARY", "SECONDARY"], @rs.status["members"].map{|member| member["stateStr"]}.sort)
  end

  def test_config
    puts
    config = @@rs.config
    pp config
    assert_equal(["0", "1", "2"], config["members"].map{|member| member["tags"]["node"]})
  end

  def test_status
    puts
    status = @@rs.status
    pp status
    assert_equal(["PRIMARY", "SECONDARY", "SECONDARY"], status["members"].map{|member| member["stateStr"]}.sort)
  end

  def test_mongo_shell
    ENV.delete('MONGO_SHELL')
    assert_nothing_raised do
      ms = Mongo::Shell.new(:port => 40001)
      ms.stop
    end
    ENV['MONGO_SHELL'] = 'xyzzy'
    assert_raise Errno::ENOENT do
      Mongo::Shell.new(:port => 40001)
    end
    ENV['MONGO_SHELL'] = '../mongo/mongo'
    assert_nothing_raised do
      ms = Mongo::Shell.new(:port => 40001)
      ms.stop
    end
  end
end
