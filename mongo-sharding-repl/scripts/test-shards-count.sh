
echo "shard 1 repl 1:"
docker compose exec -T shard1-repl1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "shard 1 repl 2:"
docker compose exec -T shard1-repl2 mongosh --port 27021 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "shard 2 repl 1:"
docker compose exec -T shard2-repl1 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "shard 2 repl 2:"
docker compose exec -T shard2-repl2 mongosh --port 27023 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF