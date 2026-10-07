# Releases and GHCR publication

For the image's purpose and supported contract, start at the [repository introduction](../README.md). This page explains how a tested commit becomes a semantic release in GitHub Container Registry.

## How does a release happen?

The [`Release` workflow](../.github/workflows/release.yml) runs after `CI` succeeds on `main`. Release Please reads Conventional Commit messages and maintains a release pull request containing the next `version.txt` value and changelog entry. Merging that pull request starts CI again; after it succeeds, Release Please creates a `vMAJOR.MINOR.PATCH` GitHub release and the same workflow builds and publishes the image.

`fix:` increments the patch version, `feat:` increments the minor version, and a breaking change increments the major version.

Branch protection should require the `Image (linux/amd64)` CI job before merges to `main`. That is the quality gate Release Please relies on.

## Which tags are published?

For release `1.2.3` at commit `012345...`, GHCR receives:

| Tag | Mutability | Intended use |
| --- | --- | --- |
| `1.2.3` | Immutable by convention | Production pin |
| `1.2` | Moves within the minor line | Automatic patch updates |
| `1` | Moves within the major line | Automatic compatible updates |
| `latest` | Moves on every stable release | Development and discovery |
| full Git SHA | Immutable by convention | Existing Chronicle Keeper compatibility and audit |
| `sha-0123456789ab` | Immutable by convention | Readable audit reference |

Every release is a Linux AMD64 image and includes BuildKit provenance plus an SBOM attestation.

## How is the image build cached?

CI stores the BuildKit cache for the AMD64 image job because its compiled extension artifacts are architecture-specific. The release build imports that cache, so it can reuse the compilation already validated by CI instead of rebuilding the extensions. It also reads the release cache as a fallback for manual republish runs. A cache miss is safe: BuildKit regenerates the layers from the pinned inputs.

## Which GitHub permissions are required?

GHCR publication utilizes the repository-scoped `GITHUB_TOKEN`; no personal registry token is required. In repository settings, allow GitHub Actions to create pull requests. Keep the workflow permission default restrictive—the individual jobs request only `contents: write`, `pull-requests: write`, or `packages: write` where needed.

For strict branch protection, add a fine-grained token as the `RELEASE_PLEASE_TOKEN` repository secret with access limited to this repository's contents and pull requests. GitHub suppresses workflow events caused by its built-in `GITHUB_TOKEN`, so the dedicated token lets the release pull request receive normal CI checks. If the secret is absent, Release Please falls back to `GITHUB_TOKEN`; in that mode, manually run `CI` against the release pull request branch before merging it.

The existing package is `ghcr.io/chroniclekeeper/chroniclekeeper-postgres`. Because it was first published by ChronicleKeeperSaaS, an organization owner must grant this new repository write access in the package's **Manage Actions access** settings, or reconnect the package to this repository. Do this before the first release; otherwise GHCR correctly rejects the push with `permission_denied`.

Fresh-image and existing-volume CI checks validate the source revision; they do not publish it or update a consumer's pinned database digest. Coordinate extension-changing releases with the consuming application's explicit migrations. After publication, set the Atlavium application's repository Actions variable `POSTGRES_IMAGE` to `ghcr.io/chroniclekeeper/chroniclekeeper-postgres@sha256:<published-digest>`, run its CI/release against that image, and select the same digest in production. Its previous-image fallback cannot satisfy the new migration prerequisite. Publication success and production upgrade success remain separate checks.

## How do you retry a failed publication?

Creating the GitHub release and pushing the image are separate operations. If the image build or registry push fails after the release exists, open the `Release` workflow, choose **Run workflow**, and enter the existing stable tag such as `v1.2.3`. The workflow validates the tag, checks out that exact release, and republishes all tags from the same commit.

Do not invent a new tag merely to retry infrastructure. Once publication succeeds, verify it with:

```bash
docker buildx imagetools inspect \
  ghcr.io/chroniclekeeper/chroniclekeeper-postgres:1.2.3
```

Please update this page whenever package ownership, release policy, or published tag behavior changes.
