ShardingTest.prototype.restart = function() {

    for ( var i = 0; i < this._mongos.length; i++ ){
        try {
            this._mongos[i].getDB('admin').runCommand({ismaster: 1});
        }
        catch (err) {
            this.restartMongos(i);
        }
    }

    return this._mongos;
}
