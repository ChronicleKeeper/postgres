#!/usr/bin/env bash

set -euo pipefail

readonly database_name="${POSTGRES_DB:-chroniclekeeper}"

# These extensions are part of the image contract. The official PostgreSQL
# entrypoint runs this script only while initializing a new data directory.
psql --set=ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$database_name" <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_textsearch;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS unaccent;
SQL
