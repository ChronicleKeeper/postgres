# Operations and extension upgrades

For the image contract and first-start behavior, start at the [repository introduction](../README.md) and [image configuration](image.md). This page covers the boundary between replacing a container image and changing an existing PostgreSQL data directory.

## Does replacing the image upgrade the database?

Not completely. A new container supplies new extension binaries and SQL migration files, but an existing data volume keeps the installed extension catalog version. The initialization scripts do not run again. This separation is deliberate: an image rollout must not silently rewrite extension metadata or rebuild application indexes.

Before deploying a dependency update, read the upstream extension release notes and determine whether it needs `ALTER EXTENSION`, `REINDEX`, a PostgreSQL restart, or a dump/restore. Test the exact consumer schema against a copy of production data where practical.

## A safe upgrade sequence

1. Read the PostgreSQL, [pgvector](https://github.com/pgvector/pgvector/releases), and [pg_textsearch](https://github.com/timescale/pg_textsearch/releases) release notes that span the change.
2. Back up the database and verify that the backup can be restored. For a large environment, take a volume snapshot in addition to a logical backup when your platform supports it.
3. Build and smoke-test the candidate image in this repository.
4. Update the consuming application's migration path. Keep extension SQL changes and any required index rebuild explicit there.
5. Exercise a staging deployment with an existing data volume, not only a fresh database.
6. Schedule downtime or concurrent index maintenance according to the upstream upgrade requirements.
7. Pin the released image version in the consumer and deploy it before applying `ALTER EXTENSION`.
8. Verify extension versions, application migrations, representative vector and search queries, logs, and backup health.

Why deploy the binary first? PostgreSQL can only execute an extension's update script after the target files exist on disk. Reversing those two steps makes the migration fail before it can change the catalog.

## Current coordinated extension upgrade

The image ships `pg_textsearch` `1.3.1` and `pgvector` `0.8.6`. Chronicle Keeper Unified migration `Version20260821100000` advances the extension catalogs after the new image is running. Its older `Version20260421140000` migration follows the installed version rather than requesting a `1.0.0` downgrade, so a fresh realm can migrate directly on the new image.

For existing data volumes, deploy the image first and then run the Unified realm migration command. Verify both catalogs afterward:

```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('pg_textsearch', 'vector')
ORDER BY extname;
```

`pg_textsearch` `1.1.0` documents `ALTER EXTENSION ... UPDATE` from `1.0.0` without a reindex. Releases `1.2.0` and `1.3.1` add replication and concurrent-write correctness fixes; the Unified migration intentionally leaves existing BM25 indexes in place and its language synchronizer rebuilds only indexes whose text configuration is wrong.

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
