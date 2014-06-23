ReplSetTest.prototype.restartSet = function() {
    for(var i=0; i<this.nodes.length; i++) {
        try {
            var reply = this.nodes[0].getDB('admin').runCommand({ismaster: 1});
            print("nodes[0]:");
            printjson(reply);
        }
        catch (err) {
            print("nodes[0] - ismaster failed\n");
            this.restart(i);
        }
    }
};



