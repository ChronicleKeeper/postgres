#!/usr/bin/env bash

wait_for_postgres() {
    local ready_container="$1"
    local ready_database="$2"
    local attempt

    # TCP is unavailable on the entrypoint's temporary initialization server.
    for attempt in {1..60}; do
        if docker exec "$ready_container" \
            psql --host=127.0.0.1 --username=postgres --dbname="$ready_database" \
            --tuples-only --no-align --command='SELECT 1' 2>/dev/null | grep --quiet '^1$'; then
            return
        fi
        sleep 1
    done

    docker logs "$ready_container"
    echo "PostgreSQL did not become ready in time." >&2
    return 1
}
