IMAGE ?= chroniclekeeper-postgres:dev
ACTIONLINT_IMAGE ?= rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
HADOLINT_IMAGE ?= hadolint/hadolint:v2.14.0-alpine@sha256:7aba693c1442eb31c0b015c129697cb3b6cb7da589d85c7562f9deb435a6657c

.DEFAULT_GOAL := test

.PHONY: build check lint test

build:
	docker build --pull --tag "$(IMAGE)" .

check:
	bash -n initdb/00-create-extensions.sh scripts/test-image.sh
	jq --exit-status 'type == "object"' .release-please-manifest.json release-please-config.json >/dev/null

lint: check
	docker run --rm --volume "$(CURDIR):/repo" --workdir /repo "$(ACTIONLINT_IMAGE)"
	docker run --rm --interactive "$(HADOLINT_IMAGE)" < Dockerfile

test: check
	IMAGE="$(IMAGE)" scripts/test-image.sh
