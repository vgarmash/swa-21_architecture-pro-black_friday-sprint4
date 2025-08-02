
Для инициализации шардирования и заполнения шардов делать ничего не нужно, все настройки запускаются за счет дополнительного контейнера с запуском инициализационных скриптов.

bash -c "
        echo 'Waiting for configSrv container...';
        until mongosh --host configSrv:27017 --eval 'db.runCommand({ ping: 1 })' | grep ok; do sleep 2; done;

        echo 'Initializing config server...';
        mongosh --host configSrv:27017 /scripts/init-config.js;

        echo 'Waiting for shard1 container...';
        until mongosh --host shard1:27018 --eval 'db.runCommand({ ping: 1 })' | grep ok; do sleep 2; done;

        echo 'Initializing shard1...';
        mongosh --host shard1:27018 /scripts/init-shard1.js;

        echo 'Waiting for shard2 container...';
        until mongosh --host shard2:27019 --eval 'db.runCommand({ ping: 1 })' | grep ok; do sleep 2; done;

        echo 'Initializing shard2...';
        mongosh --host shard2:27019 /scripts/init-shard2.js;

        echo 'Waiting for mongos_router to be available...';
        until mongosh --host mongos_router:27020 --eval 'db.runCommand({ ping: 1 })' | grep ok; do sleep 2; done;

        echo 'Adding shards to mongos...';
        mongosh --host mongos_router:27020 /scripts/init-router.js;

        echo 'Sharded cluster initialized.';

        echo 'Seeding data'

        mongosh --host mongos_router:27020 --eval '

        const somedb = db.getSiblingDB(\"somedb\");
        var docList = [];
        for(var i = 0; i < 1000; i++)
        {
          docList.push({age:i, name:\"ly\"+i});
        }
        somedb.helloDoc.insertMany(docList)'
        echo 'Data seeding completed successfully'
      "