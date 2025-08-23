### Инициализация конфигурационного кластера
1. `docker exec -it mongodb-config mongosh --port 27018 --eval "rs.initiate({ _id: 'config', configsvr: true, members: [{ _id: 0, host: 'mongodb-config:27018' }]})"`

### Инициализация кластеров с данными
2. `docker exec -it mongodb_master1 mongosh --port 27020 --eval "rs.initiate({ _id: 'rs1', members: [ { _id: 0, host: 'mongodb_master1:27020' }, { _id: 1, host: 'mongodb_replica1_1:27021' }, { _id: 2, host: 'mongodb_replica1_2:27022' } ] })"`

3. `docker exec -it mongodb_master2 mongosh --port 27030 --eval "rs.initiate({ _id: 'rs2', members: [ { _id: 0, host: 'mongodb_master2:27030' }, { _id: 1, host: 'mongodb_replica2_1:27031' }, { _id: 2, host: 'mongodb_replica2_2:27032' } ] })"`

4. `docker compose exec -T mongos-router mongosh`

5. `use admin`

6. `db.adminCommand({ addShard: "rs1/mongodb_master1:27020,mongodb_replica1_1:27021,mongodb_replica1_2:27022" })`

7. `db.adminCommand({ addShard: "rs2/mongodb_master2:27030,mongodb_replica2_1:27031,mongodb_replica2_2:27032" })`

### Настройка шардирования для бд somedb

8. `db.adminCommand({ enableSharding: "somedb" })`

9. `use somedb`

10. `db.createCollection("helloDoc")`

11. `use admin`

12. `db.adminCommand({ shardCollection: "somedb.helloDoc", key: { _id: "hashed" } })`

### Заполнение данных
13. `use somedb`

14. `for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})`

### Проверка распределения
15. `db.helloDoc.getShardDistribution()`

### Проверка данных
16. `http://localhost:8080/docs`