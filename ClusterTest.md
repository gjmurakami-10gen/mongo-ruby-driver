# Mongo Shell Cluster Testing Notes

## Work Items

### Pending

- restart/reinitialize replica set - replica_set_test_restart
- redirect log() output
- sharded cluster (minimal)
- test cluster db directories
- rake test:cleanup

### Completed

- Ruby Mongo::Shell class interface to mongo shell

    - mongo output to logfile
    - Mongo::Shell#sh output to IO arg (ex., StringIO)
    - test_connect
    - Ruby Mongo::Shell methods for replica set tests
    - psuedo-array output parsing
    - test/replica_set/basic_test.rb actually passes

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
    > var nodes = rs.startSet();
    ...
    > rs.initiate();
    ...
    > rs.awaitReplication();
    ...
    > rs.stopSet();
    ...
    > var st = new ShardingTest({shards : 2, mongos : 2, verbose : 0, separateConfig : 1});
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

## mock_replica_set

- [mock_replica_set.h](https://github.com/mongodb/mongo/blob/master/src/mongo/dbtests/mock/mock_replica_set.h)
- [mock_replica_set_test.cpp](https://github.com/mongodb/mongo/blob/master/src/mongo/dbtests/mock_replica_set_test.cpp)
