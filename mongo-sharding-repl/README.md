# Инициализация шардирования

## Шаг №1

Запускаем mongodb и приложение:

```shell
docker compose up -d
```

## Шаг №2

Подключаемся к серверу конфигурации и инициализируем его:

```shell
docker exec -it configSrv mongosh --port 27017

> rs.initiate(
  {
    _id : "config_server",
    configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
> exit();
```

## Шаг №3

Инициализируем первый и второй шарды с наборами из трех реплик:

```shell
docker exec -it mongodb1_repl1 mongosh --port 27018

> rs.initiate(
    {
      _id : "mongodb1",
      members: [
        { _id : 0, host : "mongodb1_repl1:27018" },
        { _id : 1, host : "mongodb1_repl2:27019" },
        { _id : 2, host : "mongodb1_repl3:27020" }
      ]
    }
);
> exit();

docker exec -it mongodb2_repl1 mongosh --port 27021

> rs.initiate(
    {
      _id : "mongodb2",
      members: [
        { _id : 0, host : "mongodb2_repl1:27021" },
        { _id : 1, host : "mongodb2_repl2:27022" },
        { _id : 2, host : "mongodb2_repl3:27023" }
      ]
    }
  );
> exit();
```

## Шаг №4

Инициализируем роутер и наполняем его тестовыми данными:

```shell
docker exec -it mongos_router mongosh --port 27024

> sh.addShard("mongodb1/mongodb1_repl1:27018");
> sh.addShard("mongodb2/mongodb2_repl1:27021");

> sh.enableSharding("somedb");
> sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );

> use somedb;

> for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i});

> db.helloDoc.countDocuments();
> exit();
```

Ожидаемый результат -- 1000 документов.

## Шаг №5

Проверяем на шардах:

```shell
 docker exec -it mongodb1_repl1 mongosh --port 27018
 > use somedb;
 > db.helloDoc.countDocuments();
 > exit();
 
 docker exec -it mongodb1_repl2 mongosh --port 27019
 > use somedb;
 > db.helloDoc.countDocuments();
 > exit();
 
 docker exec -it mongodb1_repl3 mongosh --port 27020
 > use somedb;
 > db.helloDoc.countDocuments();
 > exit();
 
 docker exec -it mongodb2_repl1 mongosh --port 27021
 > use somedb;
 > db.helloDoc.countDocuments();
 > exit();
 
 docker exec -it mongodb2_repl2 mongosh --port 27022
 > use somedb;
 > db.helloDoc.countDocuments();
 > exit();
 
 docker exec -it mongodb2_repl3 mongosh --port 27023
 > use somedb;
 > db.helloDoc.countDocuments();
 > exit();
 ```

Должны получиться значения N1, N2, N3, M1, M2 и M3, где N1 == N2 == N3 == N, M1 == M2 == M3 == M, N < 1000, M < 1000, N + M = 1000.