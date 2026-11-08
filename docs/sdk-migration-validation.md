# Public SDK migration validation — 2026-11-05

Repository: `kdlbs/kandev-plugin-cloudflare`, based on current default branch
`main` at `3688701fcb881e730e56e7e7187bec21dcec293b`. No repository `AGENTS.md`
exists in this checkout or at that upstream revision. The parent repository's
`create-kandev-plugin` workflow, public authoring guide, and
`docs/plans/plugin-sdk-publishing/template-migration.md` were read before changes.

This repository still contains the unrenamed template. Its module/manifest/UI
identity `kandev-plugin-template`, plugin version `0.1.0`, API v1, public `ping`
webhook, `task.created` subscription, state capability, config schema, UI bundle,
and opt-in source-control recipe are preserved. It implements no Cloudflare
provider behavior to smoke-test.

## Public dependency evidence

Both installed `sdk-release.json` files report SDK `0.1.0`, host release and
minimum host `0.99.0`, and API versions `[1, 2]`. Records were read from the
public Go module cache and installed npm package, not inferred from SDK semver.
Release: <https://github.com/kdlbs/kandev/releases/tag/pluginsdk/v0.1.0>.
Verified publication recovery: <https://github.com/kdlbs/kandev/actions/runs/42089596215>
attempt 3.

- Go: `github.com/kdlbs/kandev/pluginsdk v0.1.0`, module sum
  `h1:Pov5zE2gGf53FslhpcoGgx6E3nu6kjizT69x3MlEEEs=`.
- npm: `@kdlbs/plugin-sdk` exactly `0.1.0`; registry URL and generated integrity
  are committed in `package-lock.json`.
- No backend module requirement, SDK `replace`, npm SDK link, or `file:`
  substitution remains. All server/recipe/test imports use the public names.
  This plugin has no direct generated protobuf imports to migrate.
- Tidy adds the SDK's `google/uuid` dependency and selects gRPC `1.83.2`.
  Vitest `4.1.11` and its old lock failed the existing npm audit gate; the
  compatible `4.1.12` patch and regenerated transitive lock pass with zero
  vulnerabilities.

## Standalone checkout

Environment: Go `1.26.6`, Node `24.19.0`, npm `11.17.0`, Linux amd64. A separate
Git clone was created at `/tmp/cloudflare-sdk-migration/standalone/plugin`.
There is no sibling Kandev checkout there. Its SDK implementation resolves from
public packages; packaging tooling is an explicit input at another path.

Exact commands run from that clone:

```sh
GOWORK=off GOMODCACHE=/tmp/cloudflare-sdk-migration/standalone/gomodcache \
  GOPROXY=https://proxy.golang.org go mod download
npm ci --ignore-scripts
go mod tidy
git diff --exit-code -- go.mod go.sum
make check-format vet test sdk-check build audit-recipes
go list -m all
```

All passed. `make vet` and `make test` execute this repository's actual commands:

```sh
go vet ./server/... ./recipes/source-control/server/...
go test ./server/... ./recipes/source-control/server/...
npm run typecheck:recipes
npm run test:recipes
npm run test:ui
sh scripts/test-verify-package.sh
sh scripts/test-verify-release-version.sh
```

Both Go packages passed; recipe typecheck passed; 14 recipe tests in two files
and two UI tests passed; package and release negative tests passed. Compatibility
reports the Go and frontend SDKs compatible at minimum Kandev `0.99.0`:

```sh
go run github.com/kdlbs/kandev/pluginsdk/cmd/kandev-sdk-check@v0.1.0 \
  --manifest manifest.yaml --frontend-sdk node_modules/@kdlbs/plugin-sdk
```

The host binary builds, `npm audit --audit-level=high` reports zero
vulnerabilities, and the standalone clone remains clean. After final verifier
updates, the clone was fast-forwarded and the release regression tests rerun.

## Packaging

Tooling is independently pinned by `.kandev-tooling-ref` to
`f0e2e774cfe2df8a0d15e4c21dea7b48580e38fb`. The task-owned checkout includes
`apps/backend` and root `pluginsdk`; backend-owned `plugin-pack` runs in its own
module context. This is explicitly not checkout-free packaging.

Exact standalone commands:

```sh
CGO_ENABLED=0 make verify-package-host \
  KANDEV_TOOLING=/tmp/cloudflare-sdk-migration/tooling/apps/backend
cp kandev-plugin-template-0.1.0.tar.gz /tmp/cloudflare-sdk-migration/standalone-host-package.tar.gz
CGO_ENABLED=0 make verify-package \
  KANDEV_TOOLING=/tmp/cloudflare-sdk-migration/tooling/apps/backend
sh scripts/verify-release-version.sh v0.1.0 kandev-plugin-template-0.1.0.tar.gz
sha256sum kandev-plugin-template-0.1.0.tar.gz
tar -tzf kandev-plugin-template-0.1.0.tar.gz
```

Passed. This executor forces `CGO_ENABLED=1`; an initial cross-build failed on
foreign architecture assembly. Explicit `CGO_ENABLED=0` builds all five pure-Go
plugin executables without requiring a foreign C compiler.

Archive SHA-256 values from the standalone clone:

- Host-only: `a5f202d242e9cb694d144b65059f02a3cd9116f1fe379b4e5d6ef846f33c5df1`.
- Full: `4c4e426eb0da29d0d68b4bd1a1b7cda5aefb21463a4d4db0d4d5b33ff44017e3`.

Full inventory: `manifest.yaml`, `ui/bundle.js`, generated `checksums.txt`,
Linux amd64/arm64, Darwin amd64/arm64, and Windows amd64 `.exe` executables.
The package verifier checks exact inventory, all SHA-256 entries, and exclusion
of recipe/development files. Host-only inventory contains only Linux amd64.

The pinned packaging tool serializes YAML and narrows host-only manifest
executables. Existing verifiers rejected that output. Regression tests first
reproduced failures for serialized manifests and unquoted archive versions;
parsers now accept the real output while retaining full-platform inventory,
missing/corrupt/checksum/development-file, and release-version mismatch checks.
No checksum is authored manually.

## Minimum-host runtime

Official `v0.99.0` asset `kandev-linux-x64.tar.gz`, SHA-256
`a60656b3dbce2c663965270b22b81301e568ab39c9906f331280b4eda84294bb`, verified
with its published `.sha256` file before extraction. Runtime source commit:
`f0e2e774cfe2df8a0d15e4c21dea7b48580e38fb`.

The runtime was started with `env -i`, a task-owned HOME, XDG directories,
temporary directory/database/empty working directory, loopback bind, and
`kandev run --headless --port 28843`. `/health` reports `v0.99.0`; the backend
log reports `dist_dir: embedded`. No shared Kandev checkout was changed.

Checks performed through the disposable host's HTTP endpoints:

- Install the host archive using `POST /api/plugins/install`; status is active.
- Anonymous `POST /api/plugins/kandev-plugin-template/webhooks/ping` returns
  `Hello, webhook!`; PATCH config greeting to `Migration`, then ping returns
  `Migration, webhook!` after plugin restart.
- An undeclared webhook returns 404. Disable/re-enable yields disabled/active
  status and retains the saved greeting.
- Invalid numeric greeting returns HTTP 400 with schema error. A synthetic
  `api_token` is masked as `********` by the config GET endpoint.
- Create a disposable task without starting an agent; `task.created` reaches
  the plugin. Read-only inspection of the isolated SQLite fixture confirms
  instance-scoped `event_count` is `{"count":1}` and survives restart/lifecycle.

The Build workflow repeats archive installation, webhook, config/restart, and
lifecycle checks on a fresh official runtime. Its first run exposed a startup
race: `/health` is liveness and returns 200 before routes initialize, producing
503 on install. The workflow now waits for `/ready` and explicitly asserts
readiness before upload; runtime/plugin assertions remain unchanged.

## Browser smoke

The exact release source was built with its locked pnpm `9.15.9` dependencies,
Node 24, `KANDEV_VERSION=v0.99.0`, and empty Vite API-port/debug variables.
A task-local pnpm shim selected Corepack because this executor's global pnpm
is a different version. Playwright Chromium used existing Nix library paths.

Exact smoke command (library-path file contains only local system paths):

```sh
KANDEV_CHECKOUT=/tmp/cloudflare-sdk-migration/tooling \
KANDEV_RELEASE_SOURCE=/tmp/cloudflare-sdk-migration/tooling \
KANDEV_SMOKE_HOST_LOG=/tmp/cloudflare-sdk-migration/host/home/.kandev/logs/backend-logs.log \
KANDEV_URL=http://127.0.0.1:28843 KANDEV_EXPECTED_VERSION=v0.99.0 \
KANDEV_SMOKE_TASK_PATH=/t/1abb6710-144b-4f31-98ba-9b1eea231222 \
KANDEV_SMOKE_SCREENSHOTS=/tmp/cloudflare-sdk-migration/screenshots \
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/home/zeval/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome \
LD_LIBRARY_PATH="$(cat /tmp/cloudflare-sdk-migration/chrome-env)" \
node scripts/stable-host-smoke.mjs
```

Passed with zero page errors. The initial run exposed the old harness's
desktop-only onboarding readiness selector; it now also recognizes the mobile
navigation trigger. Actual plugin behavior and UI assertions are unchanged.

See [`sdk-migration-browser.json`](sdk-migration-browser.json) for the exact
results: 671 served embedded non-shell assets (62,997,509 bytes) match the
release build, plus 86 shell references. Asset tree SHA-256:
`4eb311004e41241262a68cd39c3b7a2d45080e4bf815e044cd5c45788f45c6c4`.
Desktop actions are 28×28; Pixel 5 actions are 44×44 at a 393px viewport.
Keyboard Enter and touch navigate to `/template`; disable removes registration
and re-enable restores exactly one. Quick Chat has no task context: send is
disabled while the navigation action remains enabled. No horizontal overflow.
Browser smoke used host archive SHA-256
`ebaaebf5f177c7b1926429882bb43aef416b188bb4b350cd4bbbe39df05a64c4`.

Only Linux amd64 runtime execution and Chromium desktop/Pixel 5 emulation were
tested. Other platforms were cross-compiled and inspected. No external provider,
real credential, agent inference, plugin release, catalog update, or merge ran.
Current exact-head CI/review status is recorded in the PR after the final push.

## Review follow-up — 2026-11-08

All six initial automated-review findings were addressed: this validation record
and browser JSON are committed; the fragment documents the base manifest's floor
without adding a duplicate key; the checker version has an explicit
`KANDEV_SDK_VERSION` upgrade step; package parsing stops at a runtime sibling;
the host mismatch regression uses a different supported platform; and browser
readiness requires visible controls plus completed onboarding state. A reordered
runtime fixture failed before the parser fix and passed afterwards. Package and
release negative tests, SDK compatibility, and npm audit passed again. The
updated browser harness was rerun against the sanitized official v0.99.0 runtime.
The corrected CI smoke step was also executed locally against a fresh runtime
and the standalone full archive; it passed installation and lifecycle assertions.
