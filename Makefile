IMAGE ?= chroniclekeeper-postgres:dev
ACTIONLINT_IMAGE ?= rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
HADOLINT_IMAGE ?= hadolint/hadolint:v2.15.1-alpine@sha256:a1d49ae1a4e83c1dbad26b8c1ad7588c8bd1e04f4866b34ad3cac50335198552

.DEFAULT_GOAL := test

.PHONY: build check lint test test-upgrade

build:
	docker build --pull --tag "$(IMAGE)" .

check:
	@for script in initdb/*.sh scripts/*.sh; do bash -n "$$script" || exit 1; done
	jq --exit-status 'type == "object"' .release-please-manifest.json release-please-config.json >/dev/null

lint: check
	docker run --rm --volume "$(CURDIR):/repo" --workdir /repo "$(ACTIONLINT_IMAGE)"
	docker run --rm --interactive "$(HADOLINT_IMAGE)" < Dockerfile

test: check
	IMAGE="$(IMAGE)" scripts/test-image.sh
	IMAGE="$(IMAGE)" SKIP_BUILD=true scripts/test-upgrade.sh

test-upgrade: check
	IMAGE="$(IMAGE)" scripts/test-upgrade.sh
