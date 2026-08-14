# Chronicle Keeper PostgreSQL

This repository delivers Chronicle Keeper's standalone PostgreSQL container image. It keeps database runtime concerns independent from the application repository while preserving the extensions and initialization behavior that Chronicle Keeper expects.

## Key concepts

- **One database image:** PostgreSQL 17, `pgvector`, `pg_textsearch`,
  `pg_trgm`, `fuzzystrmatch`, and `unaccent` are built or supplied and verified
  together.
- **Reproducible inputs:** the upstream PostgreSQL image is digest-pinned, extension source archives are version-pinned, and their SHA-256 checksums are verified during the build.
- **Safe releases:** CI smoke-tests the published architecture; Release Please turns Conventional Commits into semantic versions and publishes immutable and rolling GHCR tags.
- **Explicit ownership:** this repository owns the image. Application schemas, Doctrine migrations, backups, and production database operations remain with their consuming services.

## Why does the database have its own repository?

The old image lived below `.docker/postgres` in ChronicleKeeperSaaS. That made an application release pipeline responsible for compiling database extensions and made the image lifecycle depend on unrelated application changes. Here, a database dependency change produces a focused pull request, a focused test run, and its own release.

The image is intentionally opinionated. Utilize it when a Chronicle Keeper service needs the supported extension set with `pg_textsearch` preloaded. Prefer the upstream [`postgres`](https://hub.docker.com/_/postgres) image when a service only needs standard PostgreSQL; this repository should not become a generic collection of unrelated extensions.

## Quick start

Pull a released image:

```bash
docker run --rm --name chroniclekeeper-postgres \
  -p 5432:5432 \
  -e POSTGRES_DB=chroniclekeeper \
  -e POSTGRES_PASSWORD=postgres \
  ghcr.io/chroniclekeeper/chroniclekeeper-postgres:latest
```

For local image work, build and run the smoke suite:

```bash
make test
```

You can also start the included database-only Compose stack with `docker compose up --build`.

## What does this repository own?

The Dockerfile compiles the two third-party extensions that are not part of
PostgreSQL, copies only their installation artifacts into the runtime image,
and enables all five required extensions for newly initialized databases. The
CI pipeline verifies the server and extension versions and exercises vector
distance, trigram similarity, bounded Levenshtein distance, accent folding, and
BM25 ranking. The release pipeline publishes a Linux AMD64 image with an SBOM
and provenance attestation.

Be aware that initialization scripts only run for a new data directory. Existing volumes retain their extension catalog state and need the coordinated application migration described in the operations guide. The current Unified consumer upgrades `pg_textsearch` and `pgvector` only after this image supplies their target binaries.

## Further reading

- [Image contract and configuration](docs/image.md)
- [Development and testing](docs/development.md)
- [Releases and GHCR publication](docs/releases.md)
- [Operations and extension upgrades](docs/operations.md)

Upstream references: [PostgreSQL 17 documentation](https://www.postgresql.org/docs/17/), [pgvector](https://github.com/pgvector/pgvector), [pg_textsearch](https://github.com/timescale/pg_textsearch), and the [official PostgreSQL image documentation](https://github.com/docker-library/docs/blob/master/postgres/README.md).

If the image contract changes, please keep the implementation, smoke test, and these pages aligned in the same pull request.
