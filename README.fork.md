# ts-browser-ext — fork with exit node support

Fork of [tailscale/ts-browser-ext](https://github.com/tailscale/ts-browser-ext) with automatic exit node configuration for per-browser VPN routing.

## What this does

Routes a single browser's traffic through a Tailscale exit node **without affecting the rest of the system**. No root, no system-wide VPN changes.

The upstream extension connects to Tailscale via a self-contained `tsnet` instance but has no way to configure exit nodes — the built-in web UI only runs in `LoginServerMode` which is read-only, and the auth flow for management mode is broken for tsnet instances.

This fork patches `handleInit` to apply an exit node automatically on startup via the `TS_EXIT_NODE` environment variable.

## How it works

1. A Go binary (`ts-browser-ext`) runs as a Chrome native messaging host
2. It creates its own Tailscale identity via `tsnet` (separate from system `tailscaled`)
3. On init, if `TS_EXIT_NODE` is set, it calls `EditPrefs` to set the exit node IP
4. The extension's background script sets `chrome.proxy.settings` to route through a local SOCKS proxy the binary provides
5. Only that browser profile routes through the exit node

```
Chromium → extension proxy settings → localhost:PORT (SOCKS) → tsnet → exit node → internet
```

## Setup

### Prerequisites

- Go 1.23+
- Chromium/Chrome/Brave
- A Tailscale account with at least one exit node advertised

### Build

```bash
git clone https://github.com/BYTE-6D65/ts-browser-ext.git
cd ts-browser-ext
go build -o ts-browser-ext .
```

### Install

1. **Load the extension** in Chromium:
   - `chromium://extensions` → Developer mode → Load unpacked → select this directory
   - Note the extension ID (32-char hash)

2. **Register the native messaging host:**
   ```bash
   ./ts-browser-ext --install=C<YOUR_EXTENSION_ID>
   ```
   This writes the manifest to `~/.config/google-chrome/NativeMessagingHosts/`. If using Chromium directly, copy it:
   ```bash
   mkdir -p ~/.config/chromium/NativeMessagingHosts
   cp ~/.config/google-chrome/NativeMessagingHosts/com.tailscale.browserext.chrome.json \
      ~/.config/chromium/NativeMessagingHosts/
   ```

3. **Deploy the binary with exit node config:**
   ```bash
   # Copy the binary
   cp ts-browser-ext ~/.config/chromium/NativeMessagingHosts/ts-browser-ext.bin
   
   # Create wrapper script (sets TS_EXIT_NODE env var)
   cat > ~/.config/chromium/NativeMessagingHosts/ts-browser-ext << 'EOF'
   #!/bin/bash
   export TS_EXIT_NODE="100.x.x.x"  # your exit node's Tailscale IP
   exec "$(dirname "$0")/ts-browser-ext.bin" "$@" 2>>/tmp/ts-browser-ext.log
   EOF
   chmod +x ~/.config/chromium/NativeMessagingHosts/ts-browser-ext
   ```

4. **Log in and connect:**
   - Click the extension icon → log in to Tailscale
   - Toggle ON
   - Verify at https://ifconfig.me — should show the exit node's public IP

### Troubleshooting

- **Extension shows install command but you already installed:** The native messaging manifest `path` must point to the wrapper script, and the `allowed_origins` must match your extension ID. Check both `~/.config/google-chrome/` and `~/.config/chromium/` paths.
- **Extension connects but no exit node:** Check `/tmp/ts-browser-ext.log` for `[ts-browser-ext]` lines. If you see `EditPrefs exit node failed`, the exit node IP might not be reachable from the tsnet instance yet — try reloading the extension.
- **Binary changes not taking effect:** Chromium caches the running binary. Remove the extension, `rm` the old `.bin`, copy the new one, then load unpacked again. The `rm` before `cp` is important — Linux keeps the old inode alive if the process is running.
- **"skipped unselected default routes":** Normal if no exit node is set. The upstream code skips peer routes when they're not selected as exit nodes.

## Differences from upstream

| Feature | Upstream | This fork |
|---------|----------|-----------|
| Exit node config | Broken (LoginServerMode web UI) | Auto-applied via `TS_EXIT_NODE` env var |
| Web UI | Login only (read-only) | Unchanged (still login mode) |
| Debug logging | None | stderr logging to `/tmp/ts-browser-ext.log` |
| Native host | Single binary | Wrapper script + binary (for env var injection) |

The core change is ~25 lines in `handleInit` that call `lc.EditPrefs()` with `ExitNodeIP` and `ExitNodeAllowLANAccess` after tsnet starts.

## Architecture notes for agents

- The extension is a Chrome extension (manifest.json + background.js + popup.*) that talks to a Go native messaging host via stdin/stdout
- The Go binary creates a `tsnet.Server` — a fully self-contained Tailscale node in userspace
- State is stored in `~/.config/tailscale-browser-ext/<profile-uuid>/tailscaled.state`
- The proxy is HTTP CONNECT, not SOCKS5 — set via `chrome.proxy.settings` in background.js
- The native messaging host name is `com.tailscale.browserext.chrome`
- Chrome/Chromium launches the binary by path from the JSON manifest — extra env vars need a wrapper script
- The `--install` flag writes both the binary copy and the JSON manifest to `~/.config/.../NativeMessagingHosts/`

## License

Same as upstream — BSD 3-Clause (see LICENSE).
