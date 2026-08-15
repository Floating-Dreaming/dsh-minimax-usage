# PR: Add dsh-minimax-usage plugin

## Plugin info

- **Name**: `dsh-minimax-usage`
- **GitHub**: https://github.com/Floating-Dreaming/dsh-minimax-usage
- **npm**: https://www.npmjs.com/package/@floatingdeaming/minimax-usage
- **License**: MIT
- **Category**: Settings / Usage display

## What it does

Adds a "用量" (Usage) section to the DSH Settings page that shows the user's MiniMax Token Plan usage:

- **5-hour window** quota with reset countdown
- **Weekly window** quota with reset countdown
- Per-model breakdown (e.g., video赠送 credits)

Data is fetched from MiniMax's official `https://www.minimaxi.com/v1/token_plan/remains` endpoint via a DSH trusted plugin (holds the API key in the DSH main process; dynamic plugin code can't touch the key directly).

## Architecture

Two halves:

1. **Trusted plugin** (npm workspace package) — runs in DSH main process, provides `ctx.minimaxUsage.{getUsage, hasApiKey}`, hits MiniMax API with caching + rate limiting
2. **Dynamic plugin** (per-session, loaded via `cordis_define`) — host bridges `minimaxUsage` to a JSON RPC method, client renders the Settings section

If `MINIMAX_API_KEY` is not configured, the Settings section is hidden entirely (no error spam).

## Install

```powershell
# Windows
.\install.ps1 -ApiKey 'sk-cp-...'

# macOS / Linux
./install.sh --key 'sk-cp-...'

# From npm (after publish)
.\install.ps1 -Source npm -NpmName @floatingdeaming/minimax-usage -ApiKey 'sk-cp-...'
```

After install: restart DSH, then in a new session run `cordis_define` with the bundled `cordis_define_payload.json` + `cordis_run`.

## Verified against

- DSH main process: loads trusted plugin via npm workspace + cordis composition patch
- Tested on Windows 11 / PowerShell + macOS / bash

## Notes

- Requires a **MiniMax Token Plan / Subscription key**, not the metered-billing API key
- Built and iterated through 17 versions; see `changelog.md` for the journey
- MIT licensed, contributions welcome