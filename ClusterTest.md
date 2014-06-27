# Mongo Shell Cluster Testing Notes

## Status

Ruby replica set tests run in less than 3 minutes - authentication issues - 1 failure and 4 errors

- fast replica set test restart working without full teardown overhead!

    $ TEST_OPTS=-v time bundle exec rake test:replica_set
    ...
    Finished in 169.011492 seconds.
    
    96 tests, 2813 assertions, 1 failures, 4 errors, 0 pendings, 0 omissions, 0 notifications
    94.7917% passed
    
    0.57 tests/s, 16.64 assertions/s
    Coverage report generated for Unit Tests to /Users/gjm/10gen/mongo-ruby-driver/coverage. 2836 / 4472 LOC (63.42%) covered.
    [33m[Coveralls] Outside the Travis environment, not sending data.[0m
    rake aborted!
    Command failed with status (1): [ruby -I"lib:test" -I"/Users/gjm/.rvm/gems/ruby-2.1.1/gems/rake-10.1.1/lib" "/Users/gjm/.rvm/gems/ruby-2.1.1/gems/rake-10.1.1/lib/rake/rake_test_loader.rb"
     "test/replica_set/authentication_test.rb"
     "test/replica_set/basic_test.rb"
     "test/replica_set/client_test.rb"
     "test/replica_set/connection_test.rb"
     "test/replica_set/cursor_test.rb"
     "test/replica_set/insert_test.rb"
     "test/replica_set/max_values_test.rb"
     "test/replica_set/pinning_test.rb"
     "test/replica_set/query_test.rb"
     "test/replica_set/refresh_test.rb"
     "test/replica_set/replication_ack_test.rb" -v]
    
    Tasks: TOP => test:replica_set
    (See full trace by running task with --trace)
          173.89 real         7.08 user         6.64 sys

    Failing tests:
    Failure: test_auth_error(ReplicaSetAuthenticationTest)
    Error: test_auth_error_unordered(ReplicaSetAuthenticationTest)
    Error: test_auth_no_error(ReplicaSetAuthenticationTest)
    Error: test_duplicate_key_with_auth_error(ReplicaSetAuthenticationTest)
    Error: test_duplicate_key_with_auth_error_unordered(ReplicaSetAuthenticationTest)
    
    # complex_connect # excluded in testing.rake
    # read_preferences # excluded in testing.rake
    # refresh_test # commented out - @rs.add_node(n) @rs.remove_secondary_node @rs.repl_set_remove_node(2)
    # ssl # excluded in testing.rake
      
## Work Items

- refactor ReplSetTest out of Shell

- data directory parameter
- move Mongo::Shell code to cluster_test.js
- move cluster_test.js code to replsettest.js
- fix 5 ReplicaSetAuthenticationTest failures/errors
- sharded cluster test framework and tests
  shardingtest.js
- Perl - following iterative steps in plan
- test environment setup - local, Jenkins, MCI - environment variable(?) - discuss with Mike O. and others

### Pending

- rs.ensure
    ReplSetTest.prototype.ensureSet = function( options ) {
        for(var i=0; i < this.ports.length; i++) {
            if (!this.nodes[i].running()) { //
                this.restart( i, options );
            }
        }
    }

    ReplSetTest.prototype.status = function( timeout ){
        var master = this.callIsMaster()
        if( ! master ) master = this.liveNodes.slaves[0]
        return master.getDB("admin").runCommand({replSetGetStatus: 1})
    }

- repl_set_seeds_uri # see ReplSetTest.prototype.getURL
- status/restart/reinitialize replica set
- robustness for restart

- redirect log() output
- sharded cluster (minimal)
- test cluster db directories
- rake test:cleanup

     ruby -e 'puts ARGF.read.gsub(/@rs/,"\n@rs").split("\n").grep(/^@rs/).sort.join("\n")' test/replica_set/*.rb | uniq
     
     pending
     - @rs.add_node(n)
     - @rs.config['host']
     - @rs.member_by_name(pool.host_string).stop
     - @rs.remove_secondary_node
     - @rs.repl_set_get_status
     - @rs.repl_set_remove_node(2)
     - @rs.restart
     - @rs.start
     - @rs.stop_secondary

### Development execution

    $ > mongo_shell.log; time ruby -Ilib -Itest test/tools/framework_test.rb
    $ rake dev:rs_passing

see tasks/dev.rake for status of passing and failing tests
- passing tests - basic client count max_values pinning replication_ack_test
- failing tests - authentication complex_connect connection cursor insert query read_preference refresh ssl

### Repositories
                 
- mongo-ruby-driver/1.x-stable-cluster-test initial commit to https://github.com/gjmurakami-10gen/mongo-ruby-driver/tree/1.x-stable-cluster-test
- mongo/cluster-test initial commit to https://github.com/gjmurakami-10gen/mongo/tree/cluster-test

## Mongo Shell with socket interface

- I/O via socket

    We want a socket interface so that clients can connect and disconnect at will,
    starting/stopping/restarting clusters as needed,
    The PTY (psuedo-tty) interface can be problematic and only allows for one controlling client.

- I/O redirection

    I/O needs to be redirected for the cluster.
    We want command responses to go to the client, unfortunately this seems to be fixed to stdout.
    We want subprocess output, e.g., from "mongod", to not go to the client, unfortunately it is currently sent to stdout.
    The resulting intermixed output is problematic, so we need to fix this.

    After investigation of the previous redirection, we can do the following to fix this.

    1. outputFd = dup(fileno(stdout)) and also fdopen matching FILE * outputFile.
    2. in programOutputLogger.appendLine, use outputFile instead of stdout

    The following alternative doesn't preserve the output tagging and works in Linux, but needs to be checked in Windows.

    1. In the mongo shell, dup the connecting client socket to stdout
    2. In the subprocesses spawned by the mongo shell, dup console stderr to the subprocess stdout.

    - Previous redirection and I/O handling - ProgramRunner
        - child process dups pipeEnds[1] to stdout and stderr so output is redirected to the write end of the pipe
        - _pipe = pipeEnds[ 0 ] saves read end of the pipe to ProgramRunner
        - parent launches a thread for ProgramRunner instance
        - thread calls ProgramRunner::operator() that reads from _pipe
        - programOutputLogger.appendLine( _port, _pid, last ); appends to output
        - mongo* process lines are prepended with " mPORT| " where PORT is the port number of the mongo* process
        - output is to stdout using printf followed by fflush of stdout

        if ( dup2( child_stdout, STDOUT_FILENO ) == -1 || dup2( child_stdout, STDERR_FILENO ) == -1 ) {
            - shell_utils_launcher.cpp:453
        ProgramRunner::launchProcess( int child_stdout ) - shell_utils_launcher.cpp:365
        launchProcess(pipeEnds[1]); //sets _pid - shell_utils_launcher.cpp:266
        ProgramRunner::start() - shell_utils_launcher.cpp:257
        r.start() - shell_utils_launcher.cpp:549,556,571
            _pipe = pipeEnds[ 0 ]; - shell_utils_launcher.cpp:281
            int _pipe; - shell_utils_launcher.h:126
            class ProgramRunner { - shell_utils_launcher.h:109
            int ret = read( _pipe, (void *)start, lenToRead ); - shell_utils_launcher.cpp:299
            void ProgramRunner::operator()() { - shell_utils_launcher.cpp:284
            ProgramRunner r( a ); - shell_utils_launcher.cpp:559
            boost::thread t( r ); - shell_utils_launcher.cpp:561
        StartMongoProgram( const BSONObj &a, void* data ) - shell_utils_launcher.cpp:546
            scope.injectNative( "_startMongoProgram", StartMongoProgram ); - shell_utils_launcher.cpp:826
        RunMongoProgram( const BSONObj &a, void* data ) - shell_utils_launcher.cpp:554
            scope.injectNative( "_runMongoProgram", RunMongoProgram ); - shell_utils_launcher.cpp:829
        RunProgram(const BSONObj &a, void* data) - shell_utils_launcher.cpp:569
            scope.injectNative( "runProgram", RunProgram ); - shell_utils_launcher.cpp:827
            scope.injectNative( "run", RunProgram ); - shell_utils_launcher.cpp:828

        ReplSetTest.prototype.startSet = function( options ) { - replsettest.js:252
            node = this.start(n, options) - replsettest.js:258
            ReplSetTest.prototype.start = function( n , options , restart , wait ){ - replsettest.js:620
            var rval = this.nodes[n] = MongoRunner.runMongod( options ) - replsettest.js:680
            MongoRunner.runMongod = function( opts ){ - servers.js:558
            var mongod = MongoRunner.startWithArgs(opts, waitForConnect); - servers.js:584
            MongoRunner.startWithArgs = function(argArray, waitForConnect) { - servers.js:808
            var pid = _startMongoProgram.apply(null, argArray); - servers.js:813

        programOutputLogger.appendLine( _port, _pid, last ); - shell_utils_launcher.cpp:77
            void ProgramOutputMultiplexer::appendLine( int port, ProcessId pid, const char *line ) { - shell_utils_launcher.cpp:161

## Mongo Shell Cluster Testing Framework source code

- [ReplSetTest](https://github.com/mongodb/mongo/blob/master/src/mongo/shell/replsettest.js#L48)
- [ShardingTest](https://github.com/mongodb/mongo/blob/master/src/mongo/shell/shardingtest.js#L83)
- [Mongo shell](https://github.com/mongodb/mongo/tree/master/src/mongo/shell)

### Example usage

    $ mongo
    MongoDB shell version: 2.6.1
    connecting to: test
    > var rs = new ReplSetTest({name: 'test', nodes: 3, startPort: 31000});
    > rs.
    rs.ARBITER                      rs.nodeOptions
    rs.DOWN                         rs.nodes
    rs.PRIMARY                      rs.numNodes
    rs.RECOVERING                   rs.oplogSize
    rs.SECONDARY                    rs.overflow(
    rs.UP                           rs.partition(
    rs.add(                         rs.partitionOneWay(
    rs.addOneWayPartitionDelay(     rs.ports
    rs.addPartitionDelay(           rs.propertyIsEnumerable(
    rs.awaitReplication(            rs.reInitiate(
    rs.awaitSecondaryNodes(         rs.remove(
    rs.bridge(                      rs.removeOneWayPartitionDelay(
    rs.callIsMaster(                rs.removePartitionDelay(
    rs.constructor                  rs.restart(
    rs.getHashes(                   rs.shardSvr
    rs.getLastOpTimeWritten(        rs.start(
    rs.getMaster(                   rs.startPort
    rs.getNodeId(                   rs.startSet(
    rs.getOptions(                  rs.status(
    rs.getPath(                     rs.stop(
    rs.getPort(                     rs.stopMaster(
    rs.getPrimary(                  rs.stopSet(
    rs.getReplSetConfig(            rs.toLocaleString(
    rs.getSecondaries(              rs.toString(
    rs.getSecondary(                rs.unPartition(
    rs.getURL(                      rs.unPartitionOneWay(
    rs.hasOwnProperty(              rs.useHostName
    rs.host                         rs.useSeedList
    rs.initLiveNodes(               rs.valueOf(
    rs.initiate(                    rs.waitForHealth(
    rs.liveNodes                    rs.waitForIndicator(
    rs.name                         rs.waitForMaster(
    rs.nodeList(                    rs.waitForState(
    > rs.startSet();
    ...
    > rs.initiate();
    ...
    > rs.awaitReplication();
    ...
    > rs.stopSet();
    ...
    > var st = new ShardingTestShardingTest({name: "test", shards: 2, rs: {nodes: 1}, mongos: 2, other: { separateConfig: true } })
    ...
    > st.
    st.admin                  st.getOther(              st.s
    st.adminCommand(          st.getRSEntry(            st.s0
    st.awaitBalance(          st.getServer(             st.s1
    st.c0                     st.getServerName(         st.setBalancer(
    st.chunkCounts(           st.getShard(              st.shard0
    st.chunkDiff(             st.getShards(             st.shard1
    st.config                 st.hasOwnProperty(        st.shardColl(
    st.config0                st.isAnyBalanceInFlight(  st.shardCounts(
    st.constructor            st.isSharded(             st.shardGo(
    st.d0                     st.normalize(             st.startBalancer(
    st.d1                     st.onNumShards(           st.stop(
    st.getAnother(            st.pathOpts               st.stopBalancer(
    st.getChunksString(       st.printChangeLog(        st.stopMongos(
    st.getConfigIndex(        st.printChunks(           st.sync(
    st.getConnNames(          st.printCollectionInfo(   st.toLocaleString(
    st.getDB(                 st.printShardingStatus(   st.toString(
    st.getFirstOther(         st.propertyIsEnumerable(  st.valueOf(
    st.getNonPrimaries(       st.restartMongos(
    > st.stop();
    ...

### REPL as in Read-Execute-Print Loop

- read - [shellReadline](https://github.com/mongodb/mongo/blob/master/src/mongo/shell/dbshell.cpp#L792)
- execute - [scope->exec](https://github.com/mongodb/mongo/blob/master/src/mongo/shell/dbshell.cpp#L853)
- print - examine the following
    - [printf](https://github.com/mongodb/mongo/blob/master/src/mongo/shell/shell_utils_launcher.cpp#L168)
    - write
- loop - [while](https://github.com/mongodb/mongo/blob/master/src/mongo/shell/dbshell.cpp#L775)

### Command line

- --listen arg                          port to listen on
- command line options parsing - [shell_options.cpp](https://github.com/mongodb/mongo/blob/master/src/mongo/shell/shell_options.cpp)

### Mongo Shell build

    scons mongo

[Build MongoDB From Source](http://www.mongodb.org/about/contributors/tutorial/build-mongodb-from-source/)

### Launcher

- [dup2](https://github.com/mongodb/mongo/blob/master/src/mongo/shell/shell_utils_launcher.cpp#L453)

### mongo program - start/stop/run calling sequence

    ReplSetTest.prototype.start = function( n , options , restart , wait ){
      var rval = this.nodes[n] = MongoRunner.runMongod( options )
    ReplSetTest.prototype.stop = function( n , signal, wait /* wait for stop */, opts ){
      var ret = MongoRunner.stopMongod( port , signal, opts );
    MongoRunner.stopMongod = function( port, signal, opts ){
      var exitCode = stopMongod( parseInt( port ), parseInt( signal ), opts )

    scope.injectNative( "stopMongod", StopMongoProgram );
    BSONObj StopMongoProgram( const BSONObj &a, void* data ) {
      ProcessId pid = ProcessId::fromNative(int( a.firstElement().number() ));
      int code = killDb( port, ProcessId::fromNative(0), getSignal( a ), getStopMongodOpts( a ));
    int killDb( int port, ProcessId _pid, int signal, const BSONObj& opt ) {
      kill_wrapper( pid, signal, port, opt );
    inline void kill_wrapper( ProcessId pid, int sig, int port, const BSONObj& opt ) {
      TerminateProcess(registry._handles[pid], 1);
      int x = kill( pid.toNative(), sig );

    MongoRunner.runMongod = function( opts ){
      var mongod = MongoRunner.startWithArgs(opts, waitForConnect);
    MongoRunner.startWithArgs = function(argArray, waitForConnect) {
      var pid = _startMongoProgram.apply(null, argArray);
      conn = new Mongo("127.0.0.1:" + port);
    
## mock_replica_set

- [mock_replica_set.h](https://github.com/mongodb/mongo/blob/master/src/mongo/dbtests/mock/mock_replica_set.h)
- [mock_replica_set_test.cpp](https://github.com/mongodb/mongo/blob/master/src/mongo/dbtests/mock_replica_set_test.cpp)

{"set" : "test","date" : ISODate("2014-06-19T16:05:53Z"),"myState" : 1,"members" : [{"_id" : 0,"name" : "osprey.local:31000","health" : 1,"state" : 1,"stateStr" : "PRIMARY","uptime" : 671,"optime" : Timestamp(1403193283, 1),"optimeDate" : ISODate("2014-06-19T15:54:43Z"),"electionTime" : Timestamp(1403193293, 1),"electionDate" : ISODate("2014-06-19T15:54:53Z"),"self" : true},{"_id" : 1,"name" : "osprey.local:31001","health" : 1,"state" : 2,"stateStr" : "SECONDARY","uptime" : 670,"optime" : Timestamp(1403193283, 1),"optimeDate" : ISODate("2014-06-19T15:54:43Z"),"lastHeartbeat" : ISODate("2014-06-19T16:05:52Z"),"lastHeartbeatRecv" : ISODate("2014-06-19T16:05:52Z"),"pingMs" : 0,"syncingTo" : "osprey.local:31000"},{"_id" : 2,"name" : "osprey.local:31002","health" : 1,"state" : 2,"stateStr" : "SECONDARY","uptime" : 668,"optime" : Timestamp(1403193283, 1),"optimeDate" : ISODate("2014-06-19T15:54:43Z"),"lastHeartbeat" : ISODate("2014-06-19T16:05:52Z"),"lastHeartbeatRecv" : ISODate("2014-06-19T16:05:52Z"),"pingMs" : 0,"syncingTo" : "osprey.local:31000"}],"ok" : 1

## xinspect

    function xinspect(o,i){
        if(typeof i=='undefined')i='';
        if(i.length>50)return '[MAX ITERATIONS]';
        var r=[];
        for(var p in o){
            var t=typeof o[p];
            r.push(i+'"'+p+'" ('+t+') => '+(t=='object' ? 'object:'+xinspect(o[p],i+'  ') : o[p]+''));
        }
        return r.join(i+'\n');
    }
