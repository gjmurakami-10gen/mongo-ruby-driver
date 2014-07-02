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
      puts "@rs.node_list:#{@rs.node_list.inspect}"
      puts "@rs.node_list_as_ary:#{@rs.node_list.inspect}"
      puts "@rs.primary.id:#{@rs.primary.id.inspect}"
    end

    puts "@rs.primary:#{@rs.primary.inspect}"
    puts "@rs.primary_name:#{@rs.primary_name.inspect}"
    puts "@rs.secondaries:#{@rs.secondaries.inspect}"
    puts "@rs.secondary_names:#{@rs.secondary_names.inspect}"
    puts "@rs.arbiters:#{@rs.arbiters.inspect}"
    puts "@rs.arbiter_names:#{@rs.arbiter_names.inspect}"

    puts "@rs.repl_set_name:#{@rs.repl_set_name.inspect}"
    puts "@rs.repl_set_seeds:#{@rs.repl_set_seeds.inspect}"
    puts "@rs.repl_set_seeds_old:#{@rs.repl_set_seeds_old.inspect}"
    puts "@rs.repl_set_seeds_uri:#{@rs.repl_set_seeds_uri.inspect}"

    puts "@rs.servers:#{@rs.servers.inspect}"
    puts "@rs.servers.first.host:#{@rs.servers.first.host.inspect}"
    puts "@rs.servers.first.port:#{@rs.servers.first.port.inspect}"
    puts "@rs.servers.first.host_port:#{@rs.servers.first.host_port.inspect}"

    puts "@rs.replicas:#{@rs.replicas.inspect}"
  end

  def test_rs_restart
    sio = StringIO.new
    system("pgrep -fl mongo")
    #puts @rs.status
    puts "******** @rs.primary.stop ********"
    id = @rs.primary.stop
    system("pgrep -fl mongo")
    puts @rs.status
    puts "******** restartSet ********"
    puts @rs.sh("#{@rs.var}.restartSet();")
    puts @rs.sh("#{@rs.var}.awaitSecondaryNodes();")
    puts @rs.sh("#{@rs.var}.awaitReplication();")
    system("pgrep -fl mongo")
    puts @rs.status
    @@rs.restart
  end

  def test_config
    puts
    pp @@rs.config
  end

  def test_mongo_shell
    ENV['MONGO_SHELL'] = 'xyzzy'
    assert_raise Errno::ENOENT do
      Mongo::Shell.new(:port => 40001)
    end
    ENV['MONGO_SHELL'] = '../mongo/mongo'
    assert_nothing_raised do
      ms = Mongo::Shell.new(:port => 40001)
      ms.exit
    end
    ENV.delete('MONGO_SHELL')
    assert_nothing_raised do
      ms = Mongo::Shell.new(:port => 40001)
      ms.exit
    end
  end
end
