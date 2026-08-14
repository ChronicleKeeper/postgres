#!/usr/bin/env bash

set -euo pipefail

readonly image="${IMAGE:-chroniclekeeper-postgres:test}"
readonly container_name="chroniclekeeper-postgres-test-$$"
readonly database_name="chroniclekeeper_test"

cleanup() {
    docker rm --force "$container_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
    docker build --pull --tag "$image" .
fi

docker run --detach \
    --name "$container_name" \
    --env POSTGRES_DB="$database_name" \
    --env POSTGRES_HOST_AUTH_METHOD=trust \
    --env POSTGRES_USER=postgres \
    "$image" >/dev/null

readonly ready_query="SELECT count(*) = 3 FROM pg_extension WHERE extname IN ('vector', 'pg_textsearch', 'pg_trgm');"
for attempt in $(seq 1 60); do
    if docker exec "$container_name" \
        psql --tuples-only --no-align --username postgres --dbname "$database_name" \
        --command "$ready_query" 2>/dev/null | grep --quiet '^t$'; then
        break
    fi

    if [[ "$attempt" -eq 60 ]]; then
        docker logs "$container_name"
        echo "PostgreSQL did not initialize the required extensions in time." >&2
        exit 1
    fi

    sleep 1
done

docker exec --interactive "$container_name" \
    psql --set=ON_ERROR_STOP=1 --username postgres --dbname "$database_name" <<'SQL'
DO $test$
DECLARE
    actual_version text;
BEGIN
    IF current_setting('shared_preload_libraries') <> 'pg_textsearch' THEN
        RAISE EXCEPTION 'pg_textsearch is not preloaded';
    END IF;

    SELECT extversion INTO actual_version FROM pg_extension WHERE extname = 'vector';
    IF actual_version <> '0.8.6' THEN
        RAISE EXCEPTION 'expected vector 0.8.6, got %', actual_version;
    END IF;

    SELECT extversion INTO actual_version FROM pg_extension WHERE extname = 'pg_textsearch';
    IF actual_version <> '1.3.1' THEN
        RAISE EXCEPTION 'expected pg_textsearch 1.3.1, got %', actual_version;
    END IF;

    IF abs(('[1,2,3]'::vector <-> '[1,2,4]'::vector) - 1.0) > 0.000001 THEN
        RAISE EXCEPTION 'vector distance operator returned an unexpected result';
    END IF;

    IF similarity('chronicle', 'cronicle') < 0.5 THEN
        RAISE EXCEPTION 'pg_trgm similarity returned an unexpected result';
    END IF;
END
$test$;

CREATE TABLE image_smoke_documents (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content text NOT NULL
);
INSERT INTO image_smoke_documents (content) VALUES
    ('A dragon guards the old chronicle.'),
    ('The market opens at dawn.'),
    ('A quiet library holds forgotten maps.');
CREATE INDEX image_smoke_documents_bm25
    ON image_smoke_documents USING bm25 (content)
    WITH (text_config = 'english');

DO $test$
DECLARE
    first_result text;
BEGIN
    SELECT content
    INTO first_result
    FROM image_smoke_documents
    ORDER BY content <@> to_bm25query('dragon', 'image_smoke_documents_bm25')
    LIMIT 1;

    IF first_result <> 'A dragon guards the old chronicle.' THEN
        RAISE EXCEPTION 'BM25 returned an unexpected first result: %', first_result;
    END IF;
END
$test$;
SQL

# Confirm that initialization has completed and the final server process remains healthy.
sleep 1
docker exec "$container_name" pg_isready --username postgres --dbname "$database_name"

echo "Image smoke test passed for ${image}."
