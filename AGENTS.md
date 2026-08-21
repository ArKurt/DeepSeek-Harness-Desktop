# AGENTS.md

## Cursor Cloud specific instructions

This repo packages the **DeepSeek Harness Web UI** as a desktop app for three
platforms, each in its own directory: macOS (`Sources/`, Swift + SwiftUI),
Windows (`windows/`, C# WPF), and Linux (`linux/`, Electron). On the Linux cloud
VM **only the Linux/Electron target can be built and run** — the macOS and
Windows targets require their native toolchains/OSes. Scope work to `linux/`
unless told otherwise. See `README.md` and `linux/README.md` for full context.

### Linux app (`linux/`) — how it works

Electron shell that spawns a bundled Node runtime running `dsh web` (the
`@deepseek-ai/dsh` npm package) on port `3080`, then loads that local server in
a window. The `runtime/` directory (Node binary + `dsh` bundle + `integrity.json`)
is produced by `build-linux.sh --runtime-only` and is what the update script
assembles; it is heavy (downloads Node v24 + ~450 npm packages, several minutes)
so do not rebuild it unless dependencies change.

### Running / testing (non-obvious caveats)

- **GUI must run headless via `xvfb-run` with `--no-sandbox --disable-gpu`.**
  There is no display or Chromium sandbox in the container. Example:
  `xvfb-run -a env DSH_DESKTOP_HOME=/tmp/dsh ./node_modules/.bin/electron . --no-sandbox --disable-gpu`
- Dev run: `DSH_DESKTOP_DEV=1 ./node_modules/.bin/electron .` (or `npm start`).
  Dev mode skips the `integrity.json` self-check.
- The Electron binary downloads lazily on the first `electron` invocation (not
  during `npm install`), so the first launch is slow.
- Headless server-lifecycle smoke test (no GUI, fast): `npm run smoke`
  (`node test/server-manager.test.js`). Override port/home with
  `DSH_DESKTOP_PORT` / `DSH_DESKTOP_HOME`.
- App-level headless smoke test (exercises the full Electron main process +
  integrity check + `dsh web` lifecycle):
  `xvfb-run -a env DSH_DESKTOP_PORT=3098 DSH_DESKTOP_HOME=/tmp/dsh ./node_modules/.bin/electron . --smoke-test --no-sandbox --disable-gpu`
  → expect `DSH_SMOKE_READY ...` then `DSH_SMOKE_CLEAN`, exit 0. Requires
  `runtime/integrity.json` (present after runtime assembly).
- There is **no lint script** configured for the Linux package (`package.json`
  scripts are `start`, `dist`, `pack`, `smoke`).
- Do not `kill -9` the Electron main process; normal quit runs SIGTERM group
  cleanup of the spawned `dsh web` server. If port `3080` already has a server,
  the app reuses it and will not kill it on exit (expected).
- Data/session state lives in `~/.dsh` (override with `DSH_DESKTOP_HOME`); server
  log is at `${XDG_STATE_HOME:-~/.local/state}/deepseek/server.log`.

### Packaging (only if building distributables)

`build-linux.sh --skip-runtime` (AppImage/tar.gz via electron-builder)
additionally needs `rsvg-convert` (apt `librsvg2-bin`) for icon generation and
`libfuse2t64` for AppImage. Neither is required for dev run or smoke tests.

### Note on `build-linux.sh`

Current `@deepseek-ai/dsh` bundles `node-pty` 1.2.x, which ships **prebuilt**
binaries under `node-pty/prebuilds/linux-x64/` instead of compiling to
`build/Release/pty.node`. `build-linux.sh`'s native-module verification accepts
either location.
