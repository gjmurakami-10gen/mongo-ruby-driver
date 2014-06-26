ReplSetTest.prototype.restartSet = function() {

    for (var i = 0; i < this.nodes.length; i++) {
        try {
            this.nodes[i].getDB('admin').runCommand({ismaster: 1});
        }
        catch (err) {
            this.restart(i);
        }
    }

    return this.nodes;
}
