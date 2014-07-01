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

class ClusterShardingTest < Test::Unit::TestCase

  def setup
    ensure_cluster(:sc)
  end

  def test_cs_methods
    puts
    if defined? Mongo::Shell
      puts "@sc.s: #{@sc.s.inspect}"
      puts "@sc.s0: #{@sc.s0.inspect}"
      puts "@sc.s1: #{@sc.s1.inspect}"
      puts "@sc.s2: #{@sc.s2.inspect}"
      puts "@sc.config0: #{@sc.config0.inspect}"
    end
    puts "@sc.servers(:routers): #{@sc.servers(:routers).inspect}"
    puts "@sc.mongos_seeds: #{@sc.mongos_seeds.inspect}"
    #puts "@sc.member_by_name(): #{@sc.member_by_name()}"
  end

  def test_cs_restart
    sio = StringIO.new
    system("pgrep -fl mongo")
    @sc.restart
  end
end
