# Image contract and configuration

For what this image is and why it has its own lifecycle, start at the [repository introduction](../README.md). This page defines the runtime contract a consuming service can rely on.

## What is included?

| Component | Version | Purpose |
| --- | --- | --- |
| PostgreSQL | 17.11 | Database server and PostgreSQL-contrib extensions |
| pgvector | 0.8.6 | Vector columns, indexes, and distance operators |
| pg_textsearch | 1.3.1 | BM25 relevance-ranked full-text search |
| pg_trgm | 1.6 | Indexed substring and word-similarity retrieval |
| fuzzystrmatch | 1.2 | Bounded Levenshtein distance for complete-title proximity |
| unaccent | 1.1 | Accent-insensitive English/German full-text configurations |

All versions are pinned in the `Dockerfile`. PostgreSQL is pinned by
multi-platform manifest digest; the three contrib extension versions travel
with that base and are asserted by the smoke test. The source archives for
pgvector and pg_textsearch are checked against committed SHA-256 values before
compilation. pgvector's host-specific CPU optimizations are disabled so an
AMD64 build can run on a different AMD64 machine. The final stage starts again
from the clean PostgreSQL image, so compilers and source trees do not enter the
runtime image.

## What happens on first start?

The upstream PostgreSQL entrypoint initializes `POSTGRES_DB` and then executes
[`initdb/00-create-extensions.sh`](../initdb/00-create-extensions.sh). That
script enables `vector`, `pg_textsearch`, `pg_trgm`, `fuzzystrmatch`, and
`unaccent` in the selected database. If `POSTGRES_DB` is absent, the Chronicle
Keeper default is `chroniclekeeper`.

`pg_textsearch` must be available through `shared_preload_libraries`. The image's default command starts PostgreSQL with that setting. If you replace the container command, preserve the setting yourself:

```yaml
command:
  - postgres
  - -c
  - shared_preload_libraries=pg_textsearch
```

Have in mind that `/docker-entrypoint-initdb.d` only runs when `PGDATA` is empty. Attaching an existing volume will not create missing extensions or update installed versions. See [operations and extension upgrades](operations.md) before changing a running database.

## How should a service consume it?

Production deployments should pin the complete image version, for example:

```yaml
services:
  postgres:
    image: ghcr.io/chroniclekeeper/chroniclekeeper-postgres:1.2.3
    environment:
      POSTGRES_DB: chroniclekeeper
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?required}
      POSTGRES_USER: postgres
```

`latest`, major, and minor tags are convenient tracking channels, but they move. An exact semantic version is recommended for production. A full commit SHA tag is also published for audit and rollback workflows.

The image inherits normal configuration, secrets, storage, locale, and authentication behavior from the official PostgreSQL image. It deliberately does not bundle schema migrations, user creation beyond the upstream entrypoint, backup scheduling, connection pooling, or application-specific configuration.

## How can you inspect a running image?

```bash
docker exec chroniclekeeper-postgres \
  psql -U postgres -d chroniclekeeper \
  -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
```

Please keep this contract current when an extension, initialization step, or supported architecture changes.
