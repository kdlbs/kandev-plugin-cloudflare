# Repository baseline

Keep this repository's existing identity, settings, permissions, behavior, and
translations during dependency migrations. The Cloudflare repository currently
contains the unrenamed template; the SDK migration does not invent provider code.

## Public SDK and packaging contracts

Go `github.com/kdlbs/kandev/pluginsdk v0.1.0` and npm `@kdlbs/plugin-sdk`
exactly `0.1.0` resolve publicly. No sibling SDK sources are required for tests,
compilation, or frontend typechecking. Both installed `sdk-release.json` records
map SDK `0.1.0` to host `0.99.0`, minimum host `0.99.0`, and API versions `[1, 2]`.
The manifest retains API v1 and explicit public webhook access.

`.kandev-tooling-ref` separately pins backend-owned `plugin-pack` to
`f0e2e774cfe2df8a0d15e4c21dea7b48580e38fb`. Packaging requires a tooling
checkout containing `apps/backend` and root `pluginsdk`. Set `KANDEV_TOOLING`
to that checkout's absolute backend path, or use the default
`../kandev-tooling/apps/backend`. This is not checkout-free packaging.

Install locked dependencies, run `make sdk-check`, and keep the generated
`go.mod`, `go.sum`, and npm lockfile tidy. See the README for setup and deliberate
upgrade steps. The plugin version, shared SDK version, manifest API version,
and host release are independent contracts.

## Action ownership and supported slots

Use `host.ui.Action` inside a supported component slot. Use
`host.ui.ActionGroup` when one registration contributes several standard
actions. The host owns the outer button, icon box, spacing, focus treatment,
disabled style, and responsive size. The plugin owns labels, state, visibility,
callbacks, and rich content.

Do not pass `className`, `style`, `size`, `variant`, `asChild`, or location
overrides to Action. Do not put a button or another interactive control inside
Action. Use the existing Popover, Drawer, or Dialog for rich content. Keep
ordinary page, settings, and dialog buttons on `host.ui.Button`.

Action supports composer slots, `main-top-bar`, `chat-top-bar`,
`sidebar-workspace-actions`, and both app status-bar slots. See the
[pinned authoring guide](https://github.com/kdlbs/kandev/blob/f0e2e774cfe2df8a0d15e4c21dea7b48580e38fb/docs/public/plugins-authoring.md#standard-actions-in-component-slots)
for the surface behavior and accessible props.

### Icon action in a composer

This recipe keeps the current registration and selects one render path.
Feature-detect Action when older hosts remain supported.

```js
function makeIconAction(host) {
  const { jsx: h, ui } = host;

  return function IconAction() {
    const translate = host.i18n?.useTranslation?.().t;
    const label = translate
      ? translate("openPluginPage", { defaultValue: "Open plugin page" })
      : "Open plugin page";
    const Action = ui.Action;
    const onClick = () => host.navigate("/plugin");

    return typeof Action === "function"
      ? h(Action, { label, icon: myIcon(h), onClick })
      : h(
          ui.Button,
          {
            type: "button",
            variant: "ghost",
            size: "icon",
            "aria-label": label,
            onClick,
          },
          myIcon(h),
        );
  };
}

registry.registerComponent("chat-input-actions", makeIconAction(host));
```

The template uses this pattern in `ui/bundle.js`. Its Action path has no copied
button dimensions or classes. The legacy branch keeps its previous Button.

### Labelled metric in a top bar

Keep the label stable when a value changes or truncates. The value belongs in
`text`; the host bounds it for the selected surface.

```js
function makeUsageAction(host, getPercent, refresh) {
  const { jsx: h, ui } = host;

  return function UsageAction() {
    const translate = host.i18n?.useTranslation?.().t;
    const label = translate
      ? translate("providerUsage", { defaultValue: "Provider usage" })
      : "Provider usage";
    const value = `${getPercent()}%`;

    return typeof ui.Action === "function"
      ? h(ui.Action, { label, text: value, onClick: refresh })
      : h(
          ui.Button,
          { type: "button", "aria-label": label, onClick: refresh },
          value,
        );
  };
}

registry.registerComponent(
  "main-top-bar",
  makeUsageAction(host, getUsagePercent, refreshUsage),
);
```

### Grouped actions in a task top bar

Detect `Action` and `ActionGroup` separately. If either export is absent, keep
the legacy group as one fallback path.

```js
function makeTaskActions(host) {
  const { jsx: h, ui } = host;

  return function TaskActions() {
    const translate = host.i18n?.useTranslation?.().t;
    const label = (key, fallback) =>
      translate ? translate(key, { defaultValue: fallback }) : fallback;
    const Action = ui.Action;
    const ActionGroup = ui.ActionGroup;
    const refresh = () => refreshTask();
    const open = () => openTaskPage();

    if (typeof Action === "function" && typeof ActionGroup === "function") {
      return h(
        ActionGroup,
        { label: label("pluginActions", "Plugin actions") },
        h(Action, {
          label: label("refreshTask", "Refresh task"),
          icon: refreshIcon(h),
          onClick: refresh,
        }),
        h(Action, {
          label: label("openTask", "Open task"),
          icon: openIcon(h),
          onClick: open,
        }),
      );
    }

    return h(
      "div",
      { className: "flex gap-1" },
      h(ui.Button, { type: "button", "aria-label": label("refreshTask", "Refresh task"), onClick: refresh }, refreshIcon(h)),
      h(ui.Button, { type: "button", "aria-label": label("openTask", "Open task"), onClick: open }, openIcon(h)),
    );
  };
}

registry.registerComponent("chat-top-bar", makeTaskActions(host));
```

The group spacing belongs to ActionGroup on new hosts. Keep legacy spacing in
the fallback only. These examples stay in documentation; the template does
not register extra demo actions.

## Minimum-host verification

Use the official Kandev `v0.99.0` Linux x64 archive and verify its published
SHA-256 before starting a disposable host. Keep its HOME, XDG directories,
working directory, database, temporary directory, and loopback port isolated.
Never use a developer's primary instance. Verify `/health` reports `v0.99.0`.

Build with `make verify-package-host`, record its archive digest, and upload to
`POST /api/plugins/install`. Exercise webhook/config, task events and Host
state, UI registration, and disable/re-enable behavior. Full packaging uses
`make verify-package` and validates every declared executable plus checksums.

`scripts/stable-host-smoke.mjs` targets the exact v0.99.0 source commit. It
requires the release web build and Playwright in an explicit `KANDEV_CHECKOUT`;
these are browser-smoke inputs, not plugin SDK dependencies. Supply
`KANDEV_RELEASE_SOURCE`, `KANDEV_SMOKE_HOST_LOG`, `KANDEV_URL`, and a disposable
`KANDEV_SMOKE_TASK_PATH=/t/<id>`. It compares served embedded assets with the
release build, then exercises desktop and Pixel 5 task/Quick Chat actions,
keyboard/touch navigation, and disable/re-enable registration cleanup.

The previous baseline was tested on v0.97.0 before public SDK migration. Those
historical results do not establish the new minimum. Current migration commands,
results, skips, artifact hashes, and runtime evidence are recorded separately
in `sdk-migration-validation.md`.

## Local and CI checks

```sh
npm ci --ignore-scripts
go mod tidy
git diff --exit-code -- go.mod go.sum
make check-format vet test sdk-check build
make audit-recipes
make verify-package-host KANDEV_TOOLING=/absolute/path/to/tooling/apps/backend
make verify-package KANDEV_TOOLING=/absolute/path/to/tooling/apps/backend
```

Compilation/typecheck CI has no Kandev source checkout. Package and release
workflows explicitly check out pinned packaging tools, including root
`pluginsdk/`, and run SDK compatibility after dependency installation. The build
workflow installs the full archive into an isolated official v0.99.0 runtime
and checks webhook, config/restart, and disable/re-enable behavior.
`make test` covers Go server/recipe tests, frontend recipe typecheck/tests,
UI Action/fallback tests, and negative package/release-version checks.

Keep declared surfaces and opt-in recipes intact. Package verification checks
the exact manifest/UI/platform file list, generated checksums, and exclusion of
recipe/development files. Unit tests and package checks do not certify the
installed runtime; record minimum-host smoke independently.
