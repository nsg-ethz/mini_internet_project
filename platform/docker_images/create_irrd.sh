#/bin/bash

docker run -itd -p 6379:6379 --name irrd_redis redis

docker run -itd -p 5432:5432 -e POSTGRES_PASSWORD="irrd" -e POSTGRES_USER="irrd" --name irrd_postgres postgres

sleep 5

docker run -itd -p 8000:8000 -p 43:43 --name irrd irrd


