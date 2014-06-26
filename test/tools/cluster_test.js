ReplSetTest.prototype.getReplSetConfig = function() {
    var cfg = {};

    cfg['_id']  = this.name;
    cfg.members = [];

    for(i=0; i<this.ports.length; i++) {
        member = {};
        member['_id']  = i;

        var port = this.ports[i];

        member['host'] = this.host + ":" + port;
        if( this.nodeOptions[ "n" + i ] && this.nodeOptions[ "n" + i ].arbiter )
            member['arbiterOnly'] = true

        member['tags'] = {node: i.toString()};

        cfg.members.push(member);
    }

    return cfg;
}

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
