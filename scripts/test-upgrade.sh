#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

readonly image="${IMAGE:-chroniclekeeper-postgres:test}"
readonly old_image="${OLD_IMAGE:-ghcr.io/chroniclekeeper/chroniclekeeper-postgres@sha256:c96dabc8832f2c86b0cd4311ccbb4c2314c2f2bfd86fea49d3d58fb810011e4f}"
readonly container_name="chroniclekeeper-postgres-upgrade-$$"
readonly volume_name="${container_name}-data"
readonly database_name=chroniclekeeper_upgrade

cleanup() {
    docker rm --force --volumes "$container_name" >/dev/null 2>&1 || true
    docker volume rm "$volume_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "${SKIP_BUILD:-false}" != true ]]; then
    docker build --pull --tag "$image" .
fi

docker volume create "$volume_name" >/dev/null

start_database() {
    docker run --detach --name "$container_name" \
        --mount "type=volume,source=${volume_name},target=/var/lib/postgresql/data" \
        --shm-size=512m \
        --env POSTGRES_DB="$database_name" \
        --env POSTGRES_USER=postgres \
        --env POSTGRES_HOST_AUTH_METHOD=trust \
        "$1" >/dev/null
    wait_for_postgres "$container_name" "$database_name"
}

query() {
    docker exec --interactive "$container_name" \
        psql --set=ON_ERROR_STOP=1 --username=postgres --dbname="$database_name" "$@"
}

start_database "$old_image"
query <<'SQL'
DO $$
BEGIN
    IF (SELECT extversion FROM pg_extension WHERE extname = 'pg_textsearch') IS DISTINCT FROM '1.3.1'
       OR (SELECT extversion FROM pg_extension WHERE extname = 'vector') IS DISTINCT FROM '0.8.6' THEN
        RAISE EXCEPTION 'Upgrade fixture requires pg_textsearch 1.3.1 and vector 0.8.6';
    END IF;
END $$;

CREATE TABLE upgrade_documents (id integer PRIMARY KEY, content text NOT NULL, visible boolean NOT NULL);
INSERT INTO upgrade_documents VALUES (1, 'A dragon guards the ancient tower.', true);
INSERT INTO upgrade_documents SELECT id, 'A quiet market opens at dawn.', id % 2 = 0 FROM generate_series(2, 200) id;
CREATE INDEX upgrade_documents_bm25 ON upgrade_documents USING bm25 (content) WITH (text_config = 'english');

CREATE TABLE upgrade_vectors (id integer PRIMARY KEY, embedding halfvec(3));
INSERT INTO upgrade_vectors VALUES (1, '[1,0,0]'), (2, '[0,1,0]'), (3, '[0,0,1]');
CREATE INDEX upgrade_vectors_hnsw ON upgrade_vectors USING hnsw (embedding halfvec_cosine_ops);
CREATE TABLE upgrade_indexes AS
    SELECT oid, relname, pg_relation_filenode(oid) AS filenode
    FROM pg_class WHERE relname IN ('upgrade_documents_bm25', 'upgrade_vectors_hnsw');
CHECKPOINT;
SQL

docker stop "$container_name" >/dev/null
docker rm --volumes "$container_name" >/dev/null
start_database "$image"

query <<'SQL'
DO $$
BEGIN
    IF (SELECT extversion FROM pg_extension WHERE extname = 'pg_textsearch') IS DISTINCT FROM '1.3.1' THEN
        RAISE EXCEPTION 'Replacing the image must not silently upgrade the extension catalog';
    END IF;
END $$;

BEGIN;
ALTER EXTENSION pg_textsearch UPDATE TO '1.5.1';
ALTER EXTENSION vector UPDATE TO '0.8.7';
COMMIT;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM upgrade_indexes original
        LEFT JOIN pg_class current ON current.oid = original.oid
        WHERE current.oid IS NULL OR pg_relation_filenode(current.oid) <> original.filenode
    ) THEN
        RAISE EXCEPTION 'Extension upgrade unexpectedly rebuilt an existing index';
    END IF;
    IF (SELECT provolatile FROM pg_proc WHERE oid = 'bm25_text_bm25query_score(text,bm25query)'::regprocedure) <> 's' THEN
        RAISE EXCEPTION 'BM25 standalone scoring must use STABLE volatility';
    END IF;
END $$;

CREATE FUNCTION assert_upgrade_results() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    result_id integer;
BEGIN
    IF (SELECT extversion FROM pg_extension WHERE extname = 'pg_textsearch') IS DISTINCT FROM '1.5.1'
       OR (SELECT extversion FROM pg_extension WHERE extname = 'vector') IS DISTINCT FROM '0.8.7' THEN
        RAISE EXCEPTION 'Unexpected extension versions after upgrade';
    END IF;
    SELECT id INTO result_id FROM upgrade_documents WHERE visible
        ORDER BY content <@> to_bm25query('dragon', 'upgrade_documents_bm25') LIMIT 1;
    IF result_id IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Existing filtered BM25 index returned %', result_id;
    END IF;
    PERFORM set_config('enable_seqscan', 'off', true);
    PERFORM set_config('hnsw.iterative_scan', 'strict_order', true);
    SELECT id INTO result_id FROM upgrade_vectors ORDER BY embedding <=> '[1,0,0]'::halfvec LIMIT 1;
    IF result_id IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Existing HNSW index returned %', result_id;
    END IF;
END $$;
SELECT assert_upgrade_results();

INSERT INTO upgrade_documents VALUES (201, 'Newly written silver compass.', true);
UPDATE upgrade_documents SET content = 'Updated silver compass.' WHERE id = 201;
DELETE FROM upgrade_documents WHERE id = 200;
INSERT INTO upgrade_vectors VALUES (4, '[1,1,0]');
SELECT bm25_spill_index('upgrade_documents_bm25');
SELECT bm25_force_merge('upgrade_documents_bm25');
VACUUM ANALYZE upgrade_documents;
VACUUM ANALYZE upgrade_vectors;
SELECT assert_upgrade_results();
DO $$
BEGIN
    IF (SELECT count(*) FROM upgrade_documents) <> 200
       OR (SELECT id FROM upgrade_documents ORDER BY content <@> to_bm25query('compass', 'upgrade_documents_bm25') LIMIT 1) IS DISTINCT FROM 201 THEN
        RAISE EXCEPTION 'Post-upgrade writes or maintenance lost data';
    END IF;
END $$;
BEGIN;
DROP INDEX upgrade_documents_bm25;
ROLLBACK;
SELECT assert_upgrade_results();
SQL

docker restart "$container_name" >/dev/null
wait_for_postgres "$container_name" "$database_name"
query --command='SELECT assert_upgrade_results();'

echo "Existing-volume upgrade test passed for ${old_image} -> ${image}."
