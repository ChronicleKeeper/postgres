# Development and testing

For the repository's purpose and boundaries, start at the [repository introduction](../README.md). This page is for contributors changing the Dockerfile, initialization behavior, tests, or automation.

## What do you need locally?

You need Docker with BuildKit support, Bash, GNU Make, and `jq`. No local PostgreSQL toolchain is required because extension compilation happens inside the build stage.

Build the development image:

```bash
make build
```

Run the repository checks, fresh-image smoke suite, and existing-volume upgrade suite:

```bash
make test
```

Run the existing-volume suite independently when investigating upgrade compatibility:

```bash
make test-upgrade
```

Run the same workflow and Dockerfile linters utilized by CI:

```bash
make lint
```

Override the local image name when another project expects a particular tag:

```bash
make test IMAGE=chroniclekeeper-postgres:ci
```

## What does the smoke suite prove?

[`scripts/test-image.sh`](../scripts/test-image.sh) creates a fresh, temporary PostgreSQL container and verifies the behavior at the image boundary. It checks that:

- the server becomes ready with `pg_textsearch` preloaded;
- PostgreSQL and all required extensions run at their expected versions;
- vector distance, trigram similarity, bounded Levenshtein distance, and accent folding work;
- a BM25 index can be created and returns the expected first result; and
- the final PostgreSQL process remains healthy after initialization.

The script removes its temporary container on success or failure. CI runs the same suite for the `linux/amd64` image.

## What does the existing-volume suite prove?

[`scripts/test-upgrade.sh`](../scripts/test-upgrade.sh) creates a private temporary volume using the immutable published `1.2.0` image at `ghcr.io/chroniclekeeper/chroniclekeeper-postgres@sha256:c96dabc8832f2c86b0cd4311ccbb4c2314c2f2bfd86fea49d3d58fb810011e4f`. It creates BM25 and vector indexes with the old catalogs, restarts that volume with the candidate binary, and applies explicit upgrades to `pg_textsearch` `1.5.1` and `vector` `0.8.7`. Existing indexes must remain usable without rebuilding them. The suite removes its private container and volume afterward.

`make test` builds the candidate once and passes it to both suites. The scripts accept `IMAGE` and `SKIP_BUILD=true` to reuse an existing local build; the upgrade suite also accepts `OLD_IMAGE` when deliberately testing another supported source image. Changing the source image changes the compatibility claim, so retain its digest with your test evidence.

The image test exercises the extension boundary. Consumer adoption additionally needs the actual App and Realm migrations plus database-backed search tests; see [operations and extension upgrades](operations.md).

## How do you change a dependency?

Update the version and integrity value together. For a new pgvector release, for example:

```bash
curl -fsSL https://github.com/pgvector/pgvector/archive/refs/tags/vNEW_VERSION.tar.gz \
  | sha256sum
```

Put the resulting checksum into `PGVECTOR_SHA256`, check the fresh-image assertions and the explicit source/target assertions in the upgrade script, and run `make test`. PostgreSQL base refreshes must record the resolved multi-platform digest even when the human-readable patch tag remains unchanged. You can inspect that digest with:

```bash
docker buildx imagetools inspect postgres:NEW_VERSION
```

Do not upgrade `pg_textsearch` without following the compatibility work in [operations and extension upgrades](operations.md). Its on-disk and SQL migration behavior matters beyond whether the image compiles.

## What should a pull request contain?

Keep each change focused, include the relevant test adjustment, and write the squash commit in [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) form. `fix:` drives a patch release, `feat:` drives a minor release, and a `!` or `BREAKING CHANGE:` footer drives a major release.

Before requesting review, run `make test` and confirm the affected documentation is still accurate. Please add new smoke behavior at the container boundary when the image contract expands.
