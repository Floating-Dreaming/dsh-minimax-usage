// Trusted MiniMax usage plugin — runs in the DSH host Node process (NOT the dynamic sandbox).
//
// Provides the `minimaxUsage` service to dynamic plugins. The service holds the MiniMax
// API key in this process only; dynamic code can call `getUsage({ force? })` and never
// touches the key, environment, or network directly.

import { get as httpsGet } from 'https'
import { existsSync, readFileSync, statSync } from 'fs'
import { homedir } from 'os'
import { join } from 'path'

// ---- Configuration ----------------------------------------------------------
const REMAINS_URL = 'https://www.minimaxi.com/v1/token_plan/remains'
const REQUEST_TIMEOUT_MS = 15000
const MAX_RESPONSE_BYTES = 64 * 1024
const MIN_INTERVAL_MS = 10_000       // honor the user-facing 1 req / 10s guideline
const CACHE_TTL_MS = 60_000          // short-lived in-memory cache for repeated callers
const MAX_ATTEMPTS = 2               // initial + one retry for transient errors
const RETRY_BACKOFF_MS = 500

// ---- Key resolution ---------------------------------------------------------
function readKeyFromCredentialsFile() {
  const dshHome = process.env.DSH_HOME || join(homedir(), '.dsh')
  const candidates = [
    join(dshHome, '.credentials.yaml'),
    join(homedir(), '.dsh', '.credentials.yaml'),
  ]
  for (const file of candidates) {
    if (!existsSync(file)) continue
    let raw
    try {
      const st = statSync(file)
      if (st.size > 1024 * 1024) continue
      raw = readFileSync(file, 'utf8')
    } catch { continue }
    const m = /(?:(?:^|\n)\s*MINIMAX_API_KEY\s*:\s*)(?:'([^']*)'|"([^"]*)"|([^\s#\n][^\s#\n]*))/.exec(raw)
    if (m) return (m[1] ?? m[2] ?? m[3] ?? '').trim() || undefined
  }
  return undefined
}

function resolveApiKey() {
  const fromEnv = process.env.MINIMAX_API_KEY
  if (fromEnv && String(fromEnv).trim()) return String(fromEnv).trim()
  return readKeyFromCredentialsFile()
}

// ---- HTTP helper ------------------------------------------------------------
function httpRequestRaw(method, url, headers, body) {
  return new Promise((resolve, reject) => {
    let settled = false
    const finish = (fn, value) => {
      if (settled) return
      settled = true
      try { clearTimeout(timer) } catch {}
      fn(value)
    }
    const timer = setTimeout(() => {
      try { req.destroy(new Error('timeout')) } catch {}
      finish(reject, new Error('request timeout after ' + REQUEST_TIMEOUT_MS + 'ms'))
    }, REQUEST_TIMEOUT_MS)
    let m
    try {
      m = /^https?:\/\/([^/:]+)(?::(\d+))?(\/[^?#]*)?(\?[^#]*)?(#.*)?$/.exec(url)
    } catch (e) { return finish(reject, e) }
    if (!m) return finish(reject, new Error('invalid url'))
    const isHttps = url.startsWith('https')
    const opts = {
      method: (method || 'GET').toUpperCase(),
      hostname: m[1],
      port: m[2] ? Number(m[2]) : (isHttps ? 443 : 80),
      path: (m[3] || '/') + (m[4] || ''),
      headers: headers || {},
    }
    let req
    try {
      req = (isHttps ? httpsGet : require('http').request)(opts, (resp) => {
        const chunks = []
        let total = 0
        let aborted = false
        resp.on('data', (c) => {
          if (aborted) return
          total += c.length
          if (total > MAX_RESPONSE_BYTES) {
            aborted = true
            try { resp.destroy() } catch {}
            finish(reject, new Error('response too large'))
            return
          }
          chunks.push(c)
        })
        resp.on('end', () => {
          if (settled) return
          finish(resolve, {
            status: resp.statusCode || 0,
            headers: resp.headers || {},
            body: Buffer.concat(chunks).toString('utf8'),
          })
        })
        resp.on('error', (e) => finish(reject, e))
      })
    } catch (e) { return finish(reject, e) }
    req.on('error', (e) => finish(reject, e))
    if (body && (opts.method === 'POST' || opts.method === 'PUT' || opts.method === 'PATCH')) {
      try { req.write(body) } catch {}
    }
    try { req.end() } catch (e) { finish(reject, e) }
  })
}

// ---- Formatting & mapping ---------------------------------------------------
function formatResetIn(ms) {
  const totalSec = Math.max(0, Math.ceil(((ms || 0) / 1000)))
  const h = Math.floor(totalSec / 3600)
  const mSec = Math.floor((totalSec % 3600) / 60)
  const s = totalSec % 60
  if (h > 0) return h + ':' + String(mSec).padStart(2, '0') + ':' + String(s).padStart(2, '0')
  return String(mSec).padStart(2, '0') + ':' + String(s).padStart(2, '0')
}

function num(v) {
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}

function mapModel(m) {
  const total5h = num(m?.current_interval_total_count) ?? 0
  const remaining5hRaw = num(m?.current_interval_usage_count) ?? null
  const status5h = m?.current_interval_status ?? null
  const totalWeekRaw = num(m?.current_weekly_total_count)
  const remainingWeekRaw = num(m?.current_weekly_usage_count)

  // The API names these fields "usage_count" but they are actually the remaining quota.
  const remaining5h = remaining5hRaw != null ? Math.max(0, remaining5hRaw) : null
  const used5h = (total5h > 0 && remaining5h != null) ? Math.max(0, total5h - remaining5h) : null
  const usedPercent5h = (total5h > 0 && used5h != null)
    ? Math.max(0, Math.min(100, Math.round((used5h / total5h) * 100)))
    : null

  const totalWeek = totalWeekRaw != null ? totalWeekRaw : null
  const remainingWeek = remainingWeekRaw != null ? Math.max(0, remainingWeekRaw) : null
  const usedWeek = (totalWeek != null && totalWeek > 0 && remainingWeek != null)
    ? Math.max(0, totalWeek - remainingWeek)
    : null
  const usedPercentWeek = (totalWeek != null && totalWeek > 0 && usedWeek != null)
    ? Math.max(0, Math.min(100, Math.round((usedWeek / totalWeek) * 100)))
    : null

  // Prefer the plan-level percent fields the API actually exposes (more accurate
  // than per-model counts for the aggregated "Max Plan" view).
  const remainingPercent5h = num(m?.current_interval_remaining_percent)
  const remainingPercentWeek = num(m?.current_weekly_remaining_percent)

  return {
    modelName: typeof m?.model_name === 'string' && m.model_name ? m.model_name : 'Unknown Model',
    // 5-hour window
    total5h,
    remaining5h,
    used5h,
    usedPercent5h,
    remainingPercent5h,
    status5h,
    windowStart: typeof m?.start_time === 'number' ? new Date(m.start_time).toISOString() : null,
    windowEnd: typeof m?.end_time === 'number' ? new Date(m.end_time).toISOString() : null,
    resetIn5hMs: typeof m?.remains_time === 'number' ? m.remains_time : null,
    resetIn5hLabel: typeof m?.remains_time === 'number' ? formatResetIn(m.remains_time) : '',
    // weekly window
    totalWeek,
    remainingWeek,
    usedWeek,
    usedPercentWeek,
    remainingPercentWeek,
    weekStart: typeof m?.weekly_start_time === 'number' ? new Date(m.weekly_start_time).toISOString() : null,
    weekEnd: typeof m?.weekly_end_time === 'number' ? new Date(m.weekly_end_time).toISOString() : null,
    resetInWeekMs: typeof m?.weekly_remains_time === 'number' ? m.weekly_remains_time : null,
    resetInWeekLabel: typeof m?.weekly_remains_time === 'number' ? formatResetIn(m.weekly_remains_time) : '',
  }
}

// ---- Service state ----------------------------------------------------------
let inFlight = null
let lastResult = null          // { ok, statusCode, summary, models, fetchedAt, errorCode }
let lastRequestAt = 0

function buildErrorResponse(summary, statusCode, errorCode) {
  return { ok: false, statusCode, summary, models: [], errorCode, fetchedAt: new Date().toISOString() }
}

async function callOnce(apiKey) {
  const res = await httpRequestRaw('GET', REMAINS_URL, {
    Authorization: 'Bearer ' + apiKey,
    'Content-Type': 'application/json',
    Accept: 'application/json',
    'User-Agent': 'dsh-minimax-usage/1.0',
  })
  if (res.status < 200 || res.status >= 300) {
    return { _http: true, status: res.status, body: res.body }
  }
  let payload
  try { payload = JSON.parse(res.body) } catch (e) {
    return { _http: true, status: res.status, body: res.body, parseError: e }
  }
  return { _http: false, payload }
}

async function fetchUsageFromNetwork(apiKey) {
  let lastErr = null
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const r = await callOnce(apiKey)
      if (r._http) {
        const transient = r.status === 429 || (r.status >= 500 && r.status < 600)
        if (transient && attempt < MAX_ATTEMPTS) {
          await new Promise((r) => setTimeout(r, RETRY_BACKOFF_MS))
          continue
        }
        return buildErrorResponse('MiniMax 接口返回 ' + r.status, r.status, r.status === 429 ? 'rate_limited' : 'http_error')
      }
      const payload = r.payload
      const inner = (payload && typeof payload === 'object' && payload.base_resp) ? payload.base_resp : payload
      const code = inner && Number(inner.status_code) === inner.status_code ? Number(inner.status_code) : null
      if (code === 0) {
        const raw = Array.isArray(payload?.model_remains) ? payload.model_remains : []
        return {
          ok: true,
          statusCode: 0,
          summary: '查询成功',
          models: raw.map(mapModel),
          fetchedAt: new Date().toISOString(),
        }
      }
      if (code === 1004) {
        return buildErrorResponse('请检查 MINIMAX_API_KEY（需要 MiniMax Token Plan/Subscription Key，不是按量计费 API Key）', 1004, 'auth_error')
      }
      const msg = (inner && typeof inner.status_msg === 'string') ? inner.status_msg : null
      return buildErrorResponse(msg ? ('MiniMax 返回 ' + code + '：' + msg.slice(0, 120)) : 'MiniMax 返回未识别响应', code, 'api_error')
    } catch (e) {
      lastErr = e
      const isTimeout = e && /timeout/i.test(String(e.message || e))
      if (attempt < MAX_ATTEMPTS && (isTimeout || /ECONN|ENOTFOUND|ETIMEDOUT|ECONNRESET|socket hang up/i.test(String(e.message || e)))) {
        await new Promise((r) => setTimeout(r, RETRY_BACKOFF_MS))
        continue
      }
      const code = isTimeout ? 'timeout' : 'network_error'
      return buildErrorResponse(isTimeout ? '请求 MiniMax 超时' : ('网络错误：' + ((e && e.message) || e)), null, code)
    }
  }
  const e = lastErr
  return buildErrorResponse('网络错误：' + ((e && e.message) || e), null, 'network_error')
}

async function rawGetUsage() {
  const key = resolveApiKey()
  if (!key) return buildErrorResponse('缺少 MINIMAX_API_KEY（未在环境变量或 ~/.dsh/.credentials.yaml 中找到）', null, 'missing_key')
  return await fetchUsageFromNetwork(key)
}

async function getUsage(options) {
  const force = !!(options && options.force)
  const now = Date.now()
  // In-flight coalescing
  if (inFlight) return inFlight
  // Rate limit (always enforced)
  if (now - lastRequestAt < MIN_INTERVAL_MS) {
    if (lastResult) return Object.assign({}, lastResult, { cached: true })
    return buildErrorResponse('请求过于频繁，请稍后再试', null, 'rate_limited')
  }
  // Cache (only when not forced)
  if (!force && lastResult && (now - (lastResult.fetchedAt ? Date.parse(lastResult.fetchedAt) : 0) < CACHE_TTL_MS)) {
    return Object.assign({}, lastResult, { cached: true })
  }
  lastRequestAt = now
  inFlight = rawGetUsage().then((r) => {
    lastResult = r
    if (r.ok) r.fetchedAt = r.fetchedAt || new Date().toISOString()
    return r
  }).finally(() => { inFlight = null })
  return inFlight
}

function apply(ctx) {
  ctx.provide('minimaxUsage', {
    getUsage: (options) => getUsage(options || {}),
    hasApiKey: () => Boolean(resolveApiKey()),
  })
  console.log('[minimax-usage] service provided (ctx.minimaxUsage.getUsage)')

  // ---- JSON-RPC handlers for the browser client ---------------------------
  // The dynamic plugin's host half did this via `harness.handle(...)` (a global
  // provided by the dynamic-plugin IIFE wrapper). In the bundle-plugin format
  // the same call must come from the trusted plugin's apply(ctx). If `harness`
  // is exposed as a cordis service it's on ctx; otherwise it's a top-level
  // global. Try ctx first (strict-inject safe), fall back to global.
  const handlerTarget = (() => {
    if (ctx && typeof ctx.harness === 'object' && typeof ctx.harness.handle === 'function') {
      return ctx.harness
    }
    if (typeof globalThis.harness === 'object' && typeof globalThis.harness.handle === 'function') {
      return globalThis.harness
    }
    return null
  })()

  if (handlerTarget) {
    try {
      handlerTarget.handle('minimax.getUsage', async (args) => {
        try {
          const raw = await ctx.minimaxUsage.getUsage(args || {})
          return normalizeServiceOutput(raw)
        } catch (e) {
          return { ok: false, statusCode: 503, summary: 'MiniMax 用量服务不可用', models: [], errorCode: 'service_unavailable' }
        }
      })
      handlerTarget.handle('minimax.hasApiKey', async () => {
        try {
          if (!ctx.minimaxUsage || typeof ctx.minimaxUsage.hasApiKey !== 'function') {
            return { ok: false, hasKey: false, reason: 'service_unavailable' }
          }
          const has = Boolean(ctx.minimaxUsage.hasApiKey())
          return { ok: true, hasKey: has, reason: has ? 'resolved' : 'missing_key' }
        } catch (e) {
          return { ok: false, hasKey: false, reason: 'check_failed' }
        }
      })
      console.log('[minimax-usage] JSON-RPC handlers registered: minimax.getUsage, minimax.hasApiKey')
    } catch (e) {
      console.log('[minimax-usage] WARN: failed to register JSON-RPC handlers:', e && e.message)
    }
  } else {
    console.log('[minimax-usage] WARN: harness not available; client UI will show errors when calling host.call()')
  }
}

function normalizeModel(m) {
  if (!m || typeof m !== 'object') return m
  const out = Object.assign({}, m)
  out.total5h = num(pick(out, [
    'total5h', 'total_5h',
    'intervalTotalCount', 'interval_total_count',
    'current_interval_total_count'
  ]))
  out.remaining5h = num(pick(out, [
    'remaining5h', 'remaining_5h',
    'intervalRemainingCount', 'interval_remaining_count'
  ]))
  out.used5h = num(pick(out, [
    'used5h', 'used_5h',
    'intervalUsageCount', 'interval_usage_count', 'usageCount', 'usage_count',
    'current_interval_usage_count'
  ]))
  out.remainingPercent5h = num(pick(out, [
    'remainingPercent5h', 'remaining_percent_5h', 'remainingPercent',
    'intervalRemainsPercent', 'interval_remains_percent',
    'current_interval_remaining_percent',
    'availablePercent', 'available_percent'
  ]))
  out.usedPercent5h = num(pick(out, [
    'usedPercent5h', 'used_percent_5h', 'usedPercent',
    'intervalUsedPercent', 'interval_used_percent',
    'current_interval_used_percent',
    'consumedPercent'
  ]))
  out.resetIn5hMs = num(pick(out, [
    'resetIn5hMs', 'reset_in_5h_ms',
    'remainsTime', 'remains_time'
  ]))
  if (out.used5h == null && out.total5h != null && out.remaining5h != null) {
    out.used5h = out.total5h - out.remaining5h
  }
  if (out.used5h == null && out.usedPercent5h != null && out.total5h != null && out.total5h > 0) {
    out.used5h = out.usedPercent5h / 100 * out.total5h
  }
  if (out.used5h == null && out.remainingPercent5h != null && out.total5h != null && out.total5h > 0) {
    out.used5h = (100 - out.remainingPercent5h) / 100 * out.total5h
  }
  if (out.usedPercent5h == null && out.remainingPercent5h != null) {
    out.usedPercent5h = 100 - out.remainingPercent5h
  }
  if (out.usedPercent5h == null && out.used5h != null && out.total5h != null && out.total5h > 0) {
    out.usedPercent5h = out.used5h / out.total5h * 100
  }
  out.totalWeek = num(pick(out, [
    'totalWeek', 'total_week',
    'weeklyTotalCount', 'weekly_total_count',
    'current_weekly_total_count'
  ]))
  out.remainingWeek = num(pick(out, [
    'remainingWeek', 'remaining_week',
    'weeklyRemainingCount', 'weekly_remaining_count'
  ]))
  out.usedWeek = num(pick(out, [
    'usedWeek', 'used_week',
    'weeklyUsageCount', 'weekly_usage_count',
    'current_weekly_usage_count'
  ]))
  out.remainingPercentWeek = num(pick(out, [
    'remainingPercentWeek', 'remaining_percent_week', 'remainingPercentWeekly',
    'weeklyRemainsPercent', 'weekly_remains_percent',
    'current_weekly_remaining_percent'
  ]))
  out.usedPercentWeek = num(pick(out, [
    'usedPercentWeek', 'used_percent_week', 'usedPercentWeekly',
    'weeklyUsedPercent', 'weekly_used_percent',
    'current_weekly_used_percent'
  ]))
  out.resetInWeekMs = num(pick(out, [
    'resetInWeekMs', 'reset_in_week_ms',
    'weeklyRemainsTime', 'weekly_remains_time'
  ]))
  if (out.usedWeek == null && out.totalWeek != null && out.remainingWeek != null) {
    out.usedWeek = out.totalWeek - out.remainingWeek
  }
  if (out.usedWeek == null && out.usedPercentWeek != null && out.totalWeek != null && out.totalWeek > 0) {
    out.usedWeek = out.usedPercentWeek / 100 * out.totalWeek
  }
  if (out.usedWeek == null && out.remainingPercentWeek != null && out.totalWeek != null && out.totalWeek > 0) {
    out.usedWeek = (100 - out.remainingPercentWeek) / 100 * out.totalWeek
  }
  if (out.usedPercentWeek == null && out.remainingPercentWeek != null) {
    out.usedPercentWeek = 100 - out.remainingPercentWeek
  }
  if (out.usedPercentWeek == null && out.usedWeek != null && out.totalWeek != null && out.totalWeek > 0) {
    out.usedPercentWeek = out.usedWeek / out.totalWeek * 100
  }
  out.modelName = out.modelName || out.model_name || null
  out.status5h = num(pick(out, [
    'status5h', 'status_5h',
    'intervalStatus', 'interval_status',
    'current_interval_status'
  ]))
  out.statusWeek = num(pick(out, [
    'statusWeek', 'status_week',
    'weeklyStatus', 'weekly_status',
    'current_weekly_status'
  ]))
  return out
}

function normalizeServiceOutput(raw) {
  if (!raw || typeof raw !== 'object') return raw
  const out = Object.assign({}, raw)
  if (Array.isArray(raw.model_remains)) {
    out.models = raw.model_remains.map(normalizeModel)
  } else if (Array.isArray(raw.models)) {
    out.models = raw.models.map(normalizeModel)
  }
  if (raw.base_resp) {
    out.statusCode = raw.base_resp.status_code ?? out.statusCode
    out.summary = raw.base_resp.status_msg ?? out.summary
  }
  return out
}

function pick(obj, keys) {
  for (const k of keys) {
    if (obj[k] != null) return obj[k]
  }
  return null
}

export { apply, name, inject }
const name = 'minimax-usage'
const inject = []