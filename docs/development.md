# Development and testing

For the repository's purpose and boundaries, start at the [repository introduction](../README.md). This page is for contributors changing the Dockerfile, initialization behavior, tests, or automation.

## What do you need locally?

You need Docker with BuildKit support, Bash, GNU Make, and `jq`. No local PostgreSQL toolchain is required because extension compilation happens inside the build stage.

Build the development image:

```bash
make build
```

Run the repository checks and the image smoke suite:

```bash
make test
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
- all required extensions are created at their expected versions;
- vector distance and trigram similarity operators work;
- a BM25 index can be created and returns the expected first result; and
- the final PostgreSQL process remains healthy after initialization.

The script removes its temporary container on success or failure. CI runs the same suite for `linux/amd64` and `linux/arm64`; ARM64 runs through QEMU on GitHub-hosted runners, so it will take longer than a native local test.

## How do you change a dependency?

Update the version and integrity value together. For a new pgvector release, for example:

```bash
curl -fsSL https://github.com/pgvector/pgvector/archive/refs/tags/vNEW_VERSION.tar.gz \
  | sha256sum
```

Put the resulting checksum into `PGVECTOR_SHA256`, update the version assertions in the smoke script, and run `make test`. PostgreSQL base image updates should change both the human-readable tag and its multi-platform digest. You can inspect that digest with:

```bash
docker buildx imagetools inspect postgres:NEW_VERSION
```

Do not upgrade `pg_textsearch` without following the compatibility work in [operations and extension upgrades](operations.md). Its on-disk and SQL migration behavior matters beyond whether the image compiles.

## What should a pull request contain?

Keep each change focused, include the relevant test adjustment, and write the squash commit in [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) form. `fix:` drives a patch release, `feat:` drives a minor release, and a `!` or `BREAKING CHANGE:` footer drives a major release.

Before requesting review, run `make test` and confirm the affected documentation is still accurate. Please add new smoke behavior at the container boundary when the image contract expands.
