# Cursor Usage

macOS menu bar app that shows your current Cursor plan usage next to Wi‑Fi / battery.

It reuses the Cursor IDE login already on your Mac (reads the encrypted token from Cursor’s local state + Keychain). No separate Cursor account sign-in is required if Cursor is signed in.

## Requirements

- macOS 14+
- Xcode / Swift toolchain
- Cursor installed and signed in at least once

## Run

```bash
./scripts/run.sh
```

Or:

```bash
swift build -c release
./scripts/run.sh
```

A **Cursor Usage** item appears in the menu bar with the current usage %. Click it for plan spend, Auto/API/Total breakdown, and links to the dashboard.

The **first** launch may prompt for **Keychain** access to `Cursor Safe Storage` — choose **Always Allow**. After that, the session is cached under `~/Library/Application Support/CursorUsage/` so macOS should not ask again on each refresh.

Cursor does not expose a public hook/IPC for usage, so this app cannot “attach” to the running IDE; it reuses the same local login Cursor already stores.

## How it works

1. Uses a cached session when available (no Keychain prompt)
2. Otherwise decrypts `cursorAuth/accessToken` from Cursor’s local state via `Cursor Safe Storage` (once)
3. Calls Cursor’s dashboard RPC (`GetCurrentPeriodUsage`, `GetPlanInfo`) on `api2.cursor.sh`
4. Polls every 60 seconds (changeable in Settings)

These APIs are undocumented and may change. This is a community utility, not an official Cursor product.

## Quit

Open the menu bar popover → **Quit**, or:

```bash
killall CursorUsage
```
