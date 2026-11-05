.PHONY: build run test test-backend test-recipes test-ui test-package-verifier \
	test-release-version typecheck-recipes audit-recipes check-format fmt vet \
	sdk-check package package-host package-file verify-package verify-package-host clean

.DEFAULT_GOAL := build

# When you rename the plugin, update BIN and VERSION to match manifest.yaml's
# id and version (PKG_OUT is derived from them).
BIN := bin/kandev-plugin-template
VERSION := 0.1.0
STAGE := .build/stage
PKG_OUT := $(notdir $(BIN))-$(VERSION).tar.gz

# plugin-pack remains backend-owned tooling. This checkout is only needed for
# packaging, separately pinned by .kandev-tooling-ref. It must include both
# apps/backend and root pluginsdk (the backend has a local SDK replacement).
# Override with an absolute backend directory outside the plugin checkout.
KANDEV_TOOLING ?= ../kandev-tooling/apps/backend

sdk-check:
	go run github.com/kdlbs/kandev/pluginsdk/cmd/kandev-sdk-check@v0.1.0 --manifest manifest.yaml --frontend-sdk node_modules/@kdlbs/plugin-sdk

## Build the plugin binary for the host platform (development use). kandev
## itself always installs from `make package`/`package-host` output, not this.
build: sdk-check
	mkdir -p bin
	go build -o $(BIN) ./server/...

## Build + run. Mainly for -race / manual smoke checks: kandev normally spawns
## this binary itself via the go-plugin handshake, so a manually-started
## process has nothing to talk to on the other end.
run: build
	./$(BIN)

test: test-backend typecheck-recipes test-recipes test-ui test-package-verifier test-release-version

test-backend:
	go test ./server/... ./recipes/source-control/server/...

test-recipes:
	npm run test:recipes

test-ui:
	npm run test:ui

test-package-verifier:
	sh scripts/test-verify-package.sh

test-release-version:
	sh scripts/test-verify-release-version.sh

typecheck-recipes:
	npm run typecheck:recipes

audit-recipes:
	npm audit --audit-level=high

fmt:
	gofmt -l .

check-format:
	@test -z "$$(gofmt -l .)" || { echo "gofmt needed:"; gofmt -l .; exit 1; }

vet:
	go vet ./server/... ./recipes/source-control/server/...

## Cross-compile server/plugin-<goos>-<goarch>[.exe] for every platform in
## manifest.yaml's runtime.executables, stage manifest.yaml + ui/ alongside
## them, and pack the tree into $(PKG_OUT) with
## backend-owned cmd/plugin-pack from the separately pinned tooling checkout.
## Install the tarball via Settings > Plugins or curl -F package=@...
package: sdk-check
	rm -rf $(STAGE)
	mkdir -p $(STAGE)/server
	cp manifest.yaml $(STAGE)/manifest.yaml
	cp -r ui $(STAGE)/ui
	GOOS=linux   GOARCH=amd64 go build -o $(STAGE)/server/plugin-linux-amd64       ./server
	GOOS=linux   GOARCH=arm64 go build -o $(STAGE)/server/plugin-linux-arm64       ./server
	GOOS=darwin  GOARCH=amd64 go build -o $(STAGE)/server/plugin-darwin-amd64      ./server
	GOOS=darwin  GOARCH=arm64 go build -o $(STAGE)/server/plugin-darwin-arm64      ./server
	GOOS=windows GOARCH=amd64 go build -o $(STAGE)/server/plugin-windows-amd64.exe ./server
	cd "$(KANDEV_TOOLING)" && go run ./cmd/plugin-pack -dir $(CURDIR)/$(STAGE) -out $(CURDIR)/$(PKG_OUT)
	rm -rf $(STAGE)
	@echo "Wrote $(PKG_OUT)"

## Package for the host platform only — faster local iteration than the full
## 5-platform `make package` (matches plugin-pack's -platform-only).
package-host: sdk-check
	rm -rf $(STAGE)
	mkdir -p $(STAGE)/server
	cp manifest.yaml $(STAGE)/manifest.yaml
	cp -r ui $(STAGE)/ui
	go build -o $(STAGE)/server/plugin-$$(go env GOOS)-$$(go env GOARCH)$$(go env GOEXE) ./server
	cd "$(KANDEV_TOOLING)" && go run ./cmd/plugin-pack -dir $(CURDIR)/$(STAGE) -out $(CURDIR)/$(PKG_OUT) -platform-only
	rm -rf $(STAGE)
	@echo "Wrote $(PKG_OUT)"

## Build and validate the all-platform archive: plugin-pack checks the manifest;
## this additionally verifies checksums, expected binaries, and that opt-in
## recipe/development files did not leak into the generated starter package.
verify-package: package
	@set -eu; \
		tmp="$$(mktemp -d)"; \
		trap 'rm -rf "$$tmp"' EXIT; \
		tar -xzf "$(PKG_OUT)" -C "$$tmp"; \
		sh scripts/verify-package.sh "$$tmp" full

## Faster equivalent for local/CI host-platform packaging.
verify-package-host: package-host
	@set -eu; \
		tmp="$$(mktemp -d)"; \
		trap 'rm -rf "$$tmp"' EXIT; \
		tar -xzf "$(PKG_OUT)" -C "$$tmp"; \
		sh scripts/verify-package.sh "$$tmp" host "$$(go env GOOS)-$$(go env GOARCH)"

## Print the archive name without building it. Release automation uses this
## after it validates the manifest and Makefile versions.
package-file:
	@printf '%s\n' "$(PKG_OUT)"

clean:
	rm -rf bin $(STAGE) $(notdir $(BIN))-*.tar.gz
