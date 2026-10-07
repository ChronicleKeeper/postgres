# Operations and extension upgrades

For the image contract and first-start behavior, start at the [repository introduction](../README.md) and [image configuration](image.md). This page covers the boundary between replacing a container image and changing an existing PostgreSQL data directory. The consuming application's database runbook owns its complete Realm inventory and deployment integration.

## Does replacing the image upgrade the database?

A new container supplies extension binaries and SQL update files, but an existing volume keeps its extension catalog versions. Initialization scripts run only for an empty data directory. The consumer must migrate each database explicitly after replacing and restarting PostgreSQL.

The current targets are PostgreSQL `17.11`, `pg_textsearch` `1.5.1`, `pgvector` `0.8.7`, `pg_trgm` `1.6`, `fuzzystrmatch` `1.2`, and `unaccent` `1.1`. The PostgreSQL patch version stays unchanged; the pinned Debian trixie base is refreshed. PostgreSQL 18 needs a separate [`pg_upgrade` or dump/restore procedure](https://www.postgresql.org/docs/18/pgupgrade.html) and the [official image's changed storage layout](https://github.com/docker-library/docs/blob/master/postgres/README.md#pgdata). Extension support for PostgreSQL 19 beta does not make it a production target.

## What does this extension update improve?

`pg_textsearch` [1.4.0](https://github.com/timescale/pg_textsearch/releases/tag/v1.4.0) improves filtered top-k planning. Its [SQL upgrade](https://github.com/timescale/pg_textsearch/blob/v1.5.1/sql/pg_textsearch--1.3.1--1.4.0.sql) also marks standalone scoring functions `STABLE` so corpus changes and invoking-user privilege checks are evaluated correctly. [1.5.0](https://github.com/timescale/pg_textsearch/releases/tag/v1.5.0) reduces maintenance blocking and parallel-build memory, and fixes deep-scan scoring and truncation. [1.5.1](https://github.com/timescale/pg_textsearch/releases/tag/v1.5.1) fixes concurrent spill/merge corruption and maintenance in databases without the extension.

The [pgvector 0.8.7 changelog](https://github.com/pgvector/pgvector/blob/v0.8.7/CHANGELOG.md) fixes an IVFFlat-build buffer overflow and empty-input `avg` errors. These are upstream correctness and performance changes, not a measured Atlavium speedup. The consumer still needs its judged search and exact-versus-ANN checks.

The new Boolean `@@ tsquery` query path is available upstream, but Atlavium's query semantics are unchanged. Beta managed background compaction through `pg_durable` is not installed or enabled; adopting either capability requires its own semantic or operational validation.

## Prepare the release before downtime

1. Read the upstream release notes and SQL update chain that span the source and target versions.
2. Run `make test` for fresh initialization and the immutable published-image upgrade path. The [development guide](development.md#what-does-the-existing-volume-suite-prove) explains its source image and limits.
3. Test the candidate image with the consumer's actual App and Realm migrations and database-backed search tests against isolated restored data.
4. Publish the tested image, record its digest, and make the matching application image available. Consumer CI and deployment pins must reference the published candidate; a local successful build does not publish it.
5. Inventory the application database, every registered Realm database, PostgreSQL roles and tablespaces, and the matching database/application image digests. Verify the platform's complete backup and restore procedure before cutover.

## Execute the coordinated upgrade

This extension update uses a maintenance window. The platform must keep every application writer stopped until all databases pass:

1. Close traffic, drain requests, and stop web processes, ordinary and slow Messenger consumers, Scheduler, and any external writers. Prevent automatic restarts of the old application image.
2. Capture the application database, every Realm database, and PostgreSQL globals as one consistent backup set. When using separate logical dumps, keep writers stopped throughout capture. Verify the manifest and a tested restoration path.
3. Replace the database container with the recorded candidate digest, retain its existing volume, and start PostgreSQL alone. Verify readiness and `shared_preload_libraries=pg_textsearch`.
4. Select the matching new application image without starting its regular processes. Use the privileged migration connection: both target extensions require a PostgreSQL superuser for their update scripts. Point both application and Realm connections at the upgraded server. From one-shot containers with the production configuration, run these commands in order:

   ```bash
   php bin/console app:persistence:migrate --no-interaction
   php bin/console app:realm:database:migrate-all --no-interaction
   ```

5. Require successful exits from both commands and verify every database against the inventory below. One unavailable or failed Realm blocks traffic; successful migrations in other Realms remain applied, so repair the cause and retry with writers still stopped.
6. Start web, ordinary and slow Messenger consumers, and Scheduler on the same new application digest. Verify process identity, health, authenticated search, vector reads, and one write/job path, then reopen traffic.

The App and Realm `Version20261007100000` migrations share checksum-protected `migrations/Shared/Version20261007100000.sql`. The App migration upgrades only extensions already installed; the Realm migration requires both extensions from the supported baseline. Older catalogs advance explicitly to `1.5.1` and `0.8.7`; current or newer catalogs are never downgraded. Missing target files, missing update paths, or an absent/older loaded BM25 library fail with an actionable hint. The immutable Realm baseline stays unchanged. No fixture reload or migration-history compaction belongs in this rollout.

Why replace and restart the binary first? The SQL update files must exist, and PostgreSQL must load the new BM25 library before catalog migration. An image file on disk alone does not replace a library already loaded by the running server.

## Verify every database

Run these checks in the application database and each registered Realm database, retaining the database identity with its result:

```sql
SHOW server_version;
SHOW shared_preload_libraries;
SELECT current_setting('pg_textsearch.library_version', true) AS loaded_bm25_version;
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('fuzzystrmatch', 'pg_textsearch', 'pg_trgm', 'unaccent', 'vector')
ORDER BY extname;

SELECT oid::regprocedure, provolatile
FROM pg_proc
WHERE proname IN ('bm25_text_bm25query_score', 'bm25_textarray_bm25query_score');

SELECT c.relname, am.amname, i.indisvalid, i.indisready
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_am am ON am.oid = c.relam
WHERE am.amname IN ('bm25', 'hnsw', 'ivfflat')
ORDER BY c.relname;
```

Every Realm requires the target extension set and its expected search indexes; the App database may omit `pg_textsearch` and `vector`. Standalone BM25 scoring functions must have `provolatile='s'`. Compare the index inventory with the consuming application's canonical inventory and query existing BM25/HNSW indexes before reopening traffic.

The examined `1.3.1` → `1.5.1` and `0.8.6` → `0.8.7` SQL update paths do not require a rebuild. The migration retains existing indexes, and the image upgrade suite checks their object and file identities. This is scoped to the reviewed versions; do not infer the same rule for a later extension upgrade or use it to dismiss an existing corruption incident.

## How do you recover a failed upgrade?

Keep traffic and writers stopped, retain migration output and PostgreSQL logs, and repair a missing binary/update path or an unavailable Realm before rerunning the migration commands. These commands are safe to retry once the cause is fixed; fleet execution is not one cross-database transaction.

For rollback, restore the complete consistent backup set and PostgreSQL globals with the matching previous database and application image digests. Extension downgrades are unsupported. Do not simply attach a volume modified by newer extension binaries to the old image, even if an individual catalog migration failed; storage maintenance and writes can already have crossed a compatibility boundary.

## What should you inspect during an incident?

Start with the container and server state:

```bash
docker logs chroniclekeeper-postgres
docker exec chroniclekeeper-postgres pg_isready -U postgres -d chroniclekeeper
docker exec chroniclekeeper-postgres \
  psql -U postgres -d chroniclekeeper \
  -c "SHOW shared_preload_libraries" \
  -c "SELECT extname, extversion FROM pg_extension ORDER BY extname"
```

An error mentioning a missing `pg_textsearch` shared library points to an image or preload mismatch. An extension catalog version behind the image points to an unapplied application migration. A missing TOAST chunk is storage corruption and is not repaired by rebuilding BM25 indexes; preserve evidence and restore or repair the affected data according to the consuming service's database runbook.

Please add concrete recovery knowledge here after an incident so the next operator has a verified path rather than guesswork.
