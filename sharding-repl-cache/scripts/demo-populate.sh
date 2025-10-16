#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/lib/common.sh"

DB_NAME="${DB_NAME:-somedb}"
COLL_NAME="${COLL_NAME:-helloDoc}"
DOCS="${DOCS:-5000}"
BATCH="${BATCH:-1000}"

log "Populate $DB_NAME.$COLL_NAME => ${DOCS} docs (batch=${BATCH})"

JS="(function(){
  const dbName='$DB_NAME', coll='$COLL_NAME', total=$DOCS, step=$BATCH;
  const myDb=db.getSiblingDB(dbName); if (!myDb.getCollectionNames().includes(coll)) myDb.createCollection(coll);
  const c=myDb.getCollection(coll);
  for (let i=0;i<total;i+=step){
    const end=Math.min(i+step,total);
    const bulk=c.initializeUnorderedBulkOp();
    for (let j=i;j<end;j++){
      bulk.insert({
        _id: new ObjectId(),
        seq: j,
        name: 'user-'+j,
        age: (j % 48) + 18,
        email: 'user'+j+'@example.com',
        ts: new Date(),
        pad: 'x'.repeat(64)
      });
    }
    bulk.execute();
    print('inserted '+end);
  }
  print('done '+c.countDocuments({})+' total');
})();"

compose_exec mongos "mongosh --quiet --eval \"$JS\""
log "Populate done."
