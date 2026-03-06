---
name: relaunch-local-app
description: Rebuild and relaunch a locally developed app from the current workspace. Use when the user asks to restart the updated app, relaunch the current build, kill and reopen a running local binary, or verify fresh code in a desktop or CLI app after changes. Especially useful for Swift/macOS apps where the running process will not hot-reload new code.
---

# Relaunch Local App

Use this skill to turn source changes into a fresh running process.

## Workflow

1. Infer the build command, launch command, and process match from the repo before asking.
2. Prefer the bundled script for the actual restart:
   `scripts/relaunch_app.py --workdir <repo> --build-cmd '<build>' --launch-cmd '<launch>' --process-match '<match>'`
3. Tell the user exactly what was restarted and whether the process was newly launched or replaced.

## Defaults

- For Swift Package Manager desktop apps, prefer `swift build`.
- If the repo produces a local executable, prefer launching it directly from `.build/debug/...`.
- If `process-match` is not obvious, inspect the running process list with `ps -axo pid=,args=` and match on the executable path or stable binary name.
- If no process is running, skip the kill step and just build + launch.

## Permissions

- Request escalation for process inspection when sandboxed process discovery fails.
- Request escalation for `kill` when stopping a live app process outside the sandbox.
- Request escalation for launching GUI apps outside the sandbox.

## Script

- Use [scripts/relaunch_app.py](scripts/relaunch_app.py) for the restart sequence.
- Pass explicit commands instead of relying on hidden defaults when the project has unusual tooling.

## Examples

- “Relaunch FloatyDo so I can test the new build.”
- “Kill the current app and reopen the freshly built binary.”
