# @dsh-extras/minimax-usage

> DSH (DeepSeek Harness) trusted plugin that exposes the user's MiniMax Token Plan
> usage data via the `minimaxUsage` service.

## What it does

Runs in the DSH main Node process and provides:

```js
ctx.minimaxUsage.getUsage({ force?: boolean })  // Promise<{ ok, models, ... }>
ctx.minimaxUsage.hasApiKey()                    // boolean
```

Backed by `https://www.minimaxi.com/v1/token_plan/remains`. Features:

- 60s in-memory cache + 10s rate limit
- 2-attempt retry on transient errors (timeout / 5xx / 429)
- API key resolved from `MINIMAX_API_KEY` env var or `~/.dsh/.credentials.yaml`
- Normalized response shape with plan-level `remainingPercent*` fields

## Installation

This is a DSH **trusted** plugin, not a regular npm dependency. DSH loads it via
`pnpm` workspace + cordis composition patch. See the parent repo
[`dsh-minimax-usage`](https://github.com/your-org/dsh-minimax-usage) for the
`install.ps1` / `install.sh` scripts that wire it into DSH.

If you want to publish to your own npm registry:

```bash
# from this directory
npm login
npm publish --access public
```

Then in the DSH profile's `package.json`:

```json
{
  "dependencies": {
    "@dsh-extras/minimax-usage": "^1.0.0"
  }
}
```

…and run `pnpm install` in the profile root.

## API key

Set `MINIMAX_API_KEY` to a **Token Plan / Subscription key** (not the metered-billing
key). Sources checked in order:

1. `process.env.MINIMAX_API_KEY`
2. `~/.dsh/.credentials.yaml` — `MINIMAX_API_KEY: '<value>'`

Changes take effect after restarting DSH.

## Response shape

```js
{
  ok: true,
  statusCode: 0,
  summary: '查询成功',
  models: [
    {
      modelName: 'general',
      total5h: 0,
      remaining5h: 0,
      used5h: 0,
      usedPercent5h: 17,
      remainingPercent5h: 83,    // ← from current_interval_remaining_percent
      status5h: 1,
      windowStart: '2026-08-15T12:00:00.000Z',
      windowEnd:   '2026-08-15T16:00:00.000Z',
      resetIn5hMs: 9758306,
      resetIn5hLabel: '2:42:39',
      // same shape for totalWeek/remainingWeek/usedWeek/usedPercentWeek/remainingPercentWeek
    },
    // ...
  ],
  fetchedAt: '2026-08-15T13:17:21.569Z',
  cached: false
}
```

On error:

```js
{
  ok: false,
  statusCode: 1004,           // or 401, 503, null
  summary: '请检查 MINIMAX_API_KEY（需要 MiniMax Token Plan/Subscription Key，不是按量计费 API Key）',
  models: [],
  errorCode: 'auth_error',    // missing_key | auth_error | rate_limited | http_error | network_error | timeout | api_error
  fetchedAt: '2026-08-15T13:17:21.569Z'
}
```

## Why a trusted plugin?

DSH sandboxes dynamic plugin code — they cannot make network calls or read env vars
directly. To bridge to MiniMax's API we need a plugin that runs in the DSH main
process, which DSH calls "trusted". The dynamic client-side plugin (`cordis_define`
+ `cordis_run` in a session) calls `ctx.minimaxUsage.getUsage()` via Host RPC.

## License

MIT