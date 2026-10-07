#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

readonly image="${IMAGE:-chroniclekeeper-postgres:test}"
readonly container_name="chroniclekeeper-postgres-test-$$"
readonly database_name="chroniclekeeper_test"

cleanup() {
    docker rm --force --volumes "$container_name" >/dev/null 2>&1 || true
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

wait_for_postgres "$container_name" "$database_name"

docker exec --interactive "$container_name" \
    psql --set=ON_ERROR_STOP=1 --username postgres --dbname "$database_name" <<'SQL'
DO $test$
DECLARE
    actual_version text;
BEGIN
    IF current_setting('server_version') !~ '^17\.11' THEN
        RAISE EXCEPTION 'expected PostgreSQL 17.11, got %', current_setting('server_version');
    END IF;

    IF current_setting('shared_preload_libraries') <> 'pg_textsearch' THEN
        RAISE EXCEPTION 'pg_textsearch is not preloaded';
    END IF;

    SELECT extversion INTO actual_version FROM pg_extension WHERE extname = 'vector';
    IF actual_version IS DISTINCT FROM '0.8.7' THEN
        RAISE EXCEPTION 'expected vector 0.8.7, got %', actual_version;
    END IF;

    SELECT extversion INTO actual_version FROM pg_extension WHERE extname = 'pg_textsearch';
    IF actual_version IS DISTINCT FROM '1.5.1' THEN
        RAISE EXCEPTION 'expected pg_textsearch 1.5.1, got %', actual_version;
    END IF;

    SELECT extversion INTO actual_version FROM pg_extension WHERE extname = 'pg_trgm';
    IF actual_version IS DISTINCT FROM '1.6' THEN
        RAISE EXCEPTION 'expected pg_trgm 1.6, got %', actual_version;
    END IF;

    SELECT extversion INTO actual_version FROM pg_extension WHERE extname = 'fuzzystrmatch';
    IF actual_version IS DISTINCT FROM '1.2' THEN
        RAISE EXCEPTION 'expected fuzzystrmatch 1.2, got %', actual_version;
    END IF;

    SELECT extversion INTO actual_version FROM pg_extension WHERE extname = 'unaccent';
    IF actual_version IS DISTINCT FROM '1.1' THEN
        RAISE EXCEPTION 'expected unaccent 1.1, got %', actual_version;
    END IF;

    IF abs(('[1,2,3]'::vector <-> '[1,2,4]'::vector) - 1.0) > 0.000001 THEN
        RAISE EXCEPTION 'vector distance operator returned an unexpected result';
    END IF;

    IF (SELECT avg(embedding) FROM (SELECT '[1,2,3]'::vector AS embedding) sample WHERE false) IS NOT NULL THEN
        RAISE EXCEPTION 'vector average of no rows must be NULL';
    END IF;

    IF similarity('chronicle', 'cronicle') < 0.5 THEN
        RAISE EXCEPTION 'pg_trgm similarity returned an unexpected result';
    END IF;

    IF levenshtein_less_equal('cronicle', 'chronicle', 2) <> 1 THEN
        RAISE EXCEPTION 'fuzzystrmatch bounded Levenshtein returned an unexpected result';
    END IF;

    IF unaccent('Märchen') <> 'Marchen' THEN
        RAISE EXCEPTION 'unaccent returned an unexpected result';
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

docker exec "$container_name" pg_isready --host=127.0.0.1 --username postgres --dbname "$database_name"

echo "Image smoke test passed for ${image}."
