import json
import logging
import os
import time
from typing import List, Optional

import motor.motor_asyncio
from bson import ObjectId
from fastapi import Body, FastAPI, HTTPException, status
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
from fastapi_cache.decorator import cache
from logmiddleware import RouterLoggingMiddleware, logging_config
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from pydantic.functional_validators import BeforeValidator
from pymongo import errors
from redis import asyncio as aioredis
from redis.cluster import ClusterNode
from redis.exceptions import ConnectionError as RedisConnectionError
from typing_extensions import Annotated

# Configure JSON logging
logging.basicConfig(format='%(asctime)s %(message)s', datefmt='%m/%d/%Y %I:%M:%S %p', level=logging.DEBUG)
logger = logging.getLogger(__name__)

app = FastAPI()
app.add_middleware(
    RouterLoggingMiddleware,
    logger=logger
)

DATABASE_URL = os.environ["MONGODB_URL"]
DATABASE_NAME = os.environ["MONGODB_DATABASE_NAME"]
REDIS_URL = os.getenv("REDIS_URL", None)

logger.info(f"Starting application with MongoDB URL: {DATABASE_URL}")
logger.info(f"Redis URL: {REDIS_URL}")

def nocache(*args, **kwargs):
    def decorator(func):
        return func
    return decorator

if REDIS_URL:
    cache = cache
else:
    cache = nocache

try:
    client = motor.motor_asyncio.AsyncIOMotorClient(DATABASE_URL, serverSelectionTimeoutMS=5000)
    db = client[DATABASE_NAME]
    logger.info("MongoDB client initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize MongoDB client: {e}")
    raise

# Represents an ObjectId field in the database.
PyObjectId = Annotated[str, BeforeValidator(str)]

@app.on_event("startup")
async def startup():
    logger.info("Application starting up...")
    logger.info("Environment variables:")
    logger.info(f"  MONGODB_URL: {DATABASE_URL}")
    logger.info(f"  MONGODB_DATABASE_NAME: {DATABASE_NAME}")
    logger.info(f"  REDIS_URL: {REDIS_URL}")

    # Test MongoDB connection
    try:
        await client.admin.command('ping')
        logger.info("MongoDB connection: SUCCESS")
    except Exception as e:
        logger.error(f"MongoDB connection: FAILED - {e}")

    # Initialize Redis cache if available
    if REDIS_URL:
        try:
            logger.info(f"Initializing Redis cache with URL: {REDIS_URL}")

            # Для Redis кластера
            if ',' in REDIS_URL:
                # Формат: redis://host1:port1,host2:port2,host3:port3
                # Удаляем префикс redis:// и разбиваем по запятым
                nodes_str = REDIS_URL.replace('redis://', '')

                # Создаем список узлов в формате, который понимает RedisCluster
                startup_nodes = []
                for node in nodes_str.split(','):
                    host, port = node.split(':')
                    logger.info(f"host: {host}, port: {port}")
                    startup_nodes.append(ClusterNode(host, int(port)))

                # Для Redis 8.x используем правильные параметры
                redis = aioredis.RedisCluster(
                    startup_nodes=startup_nodes,
                    decode_responses=False,
                    require_full_coverage=False
                )
            else:
                # Одиночный Redis
                redis = aioredis.from_url(
                    REDIS_URL,
                    encoding="utf8",
                    decode_responses=False
                )

            # Тестируем подключение
            await redis.ping()
            logger.info("Redis connection: SUCCESS")

            # Инициализируем кэш
            FastAPICache.init(RedisBackend(redis), prefix="api:cache")
            logger.info("FastAPI Cache initialized successfully")

        except Exception as e:
            logger.error(f"Redis initialization failed: {e}")
            import traceback
            logger.error(f"Full traceback: {traceback.format_exc()}")
            # Устанавливаем cache в nocache режим
            global cache
            cache = nocache
            logger.info("Cache disabled due to Redis initialization failure")
    else:
        logger.info("Redis cache disabled - no REDIS_URL provided")

@app.get("/health")
async def health_check():
    """Health check endpoint for Docker healthcheck"""
    mongo_status = "unknown"
    redis_status = "disabled"

    try:
        await client.admin.command('ping')
        mongo_status = "healthy"
    except Exception as e:
        mongo_status = f"unhealthy: {e}"

    # Безопасная проверка Redis
    if REDIS_URL:
        try:
            # Пытаемся получить бэкенд, но ловим исключение
            backend = FastAPICache.get_backend()
            if backend:
                await backend.redis.ping()
                redis_status = "healthy"
            else:
                redis_status = "not_initialized"
        except AssertionError:
            # FastAPICache не инициализирован
            redis_status = "not_initialized"
        except Exception as e:
            redis_status = f"unhealthy: {e}"

    # Всегда возвращаем 200, главное что приложение работает
    health_status = "healthy" if mongo_status == "healthy" else "degraded"

    return {
        "status": health_status,
        "mongo": mongo_status,
        "redis": redis_status,
        "timestamp": time.time()
    }


class UserModel(BaseModel):
    """
    Container for a single user record.
    """

    id: Optional[PyObjectId] = Field(alias="_id", default=None)
    age: int = Field(...)
    name: str = Field(...)


class UserCollection(BaseModel):
    """
    A container holding a list of `UserModel` instances.
    """

    users: List[UserModel]


@app.get("/")
async def root():
    collection_names = await db.list_collection_names()
    collections = {}
    for collection_name in collection_names:
        collection = db.get_collection(collection_name)
        collections[collection_name] = {
            "documents_count": await collection.count_documents({})
        }
    try:
        replica_status = await client.admin.command("replSetGetStatus")
        replica_status = json.dumps(replica_status, indent=2, default=str)
    except errors.OperationFailure:
        replica_status = "No Replicas"

    topology_description = client.topology_description
    read_preference = client.client_options.read_preference
    topology_type = topology_description.topology_type_name
    replicaset_name = topology_description.replica_set_name

    shards = None
    if topology_type == "Sharded":
        shards_list = await client.admin.command("listShards")
        shards = {}
        for shard in shards_list.get("shards", {}):
            shards[shard["_id"]] = shard["host"]

    cache_enabled = False
    if REDIS_URL:
        cache_enabled = FastAPICache.get_enable()

    return {
        "mongo_topology_type": topology_type,
        "mongo_replicaset_name": replicaset_name,
        "mongo_db": DATABASE_NAME,
        "read_preference": str(read_preference),
        "mongo_nodes": client.nodes,
        "mongo_primary_host": client.primary,
        "mongo_secondary_hosts": client.secondaries,
        "mongo_is_primary": client.is_primary,
        "mongo_is_mongos": client.is_mongos,
        "collections": collections,
        "shards": shards,
        "cache_enabled": cache_enabled,
        "status": "OK",
    }


@app.get("/{collection_name}/count")
async def collection_count(collection_name: str):
    collection = db.get_collection(collection_name)
    items_count = await collection.count_documents({})
    # status = await client.admin.command('replSetGetStatus')
    # import ipdb; ipdb.set_trace()
    return {"status": "OK", "mongo_db": DATABASE_NAME, "items_count": items_count}


@app.get(
    "/{collection_name}/users",
    response_description="List all users",
    response_model=UserCollection,
    response_model_by_alias=False,
)
@cache(expire=60 * 1)
async def list_users(collection_name: str):
    """
    List all of the user data in the database.
    The response is unpaginated and limited to 1000 results.
    """
    time.sleep(1)
    collection = db.get_collection(collection_name)
    return UserCollection(users=await collection.find().to_list(1000))


@app.get(
    "/{collection_name}/users/{name}",
    response_description="Get a single user",
    response_model=UserModel,
    response_model_by_alias=False,
)
async def show_user(collection_name: str, name: str):
    """
    Get the record for a specific user, looked up by `name`.
    """

    collection = db.get_collection(collection_name)
    if (user := await collection.find_one({"name": name})) is not None:
        return user

    raise HTTPException(status_code=404, detail=f"User {name} not found")


@app.post(
    "/{collection_name}/users",
    response_description="Add new user",
    response_model=UserModel,
    status_code=status.HTTP_201_CREATED,
    response_model_by_alias=False,
)
async def create_user(collection_name: str, user: UserModel = Body(...)):
    """
    Insert a new user record.

    A unique `id` will be created and provided in the response.
    """
    collection = db.get_collection(collection_name)
    new_user = await collection.insert_one(
        user.model_dump(by_alias=True, exclude=["id"])
    )
    created_user = await collection.find_one({"_id": new_user.inserted_id})
    return created_user
