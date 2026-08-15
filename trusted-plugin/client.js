// DSH bundle plugin client half — renders the "用量" section in Settings.
//
// Loaded by DSH browser runtime via `window.__ModuleLoader__.load({id, factory})`
// after the host half (trusted-plugin/index.js) registers `minimax.getUsage` and
// `minimax.hasApiKey` JSON-RPC handlers. The component uses `ctx.host.call(...)`
// to fetch data through those handlers.
//
// This file mirrors the v17 dynamic-plugin client (cordis_define_payload.json),
// adapted to the CJS bundle format:
//   - React / runtime services are `require()`-ed or come from `ctx`
//   - CSS is injected via a `<style>` element (the dynamic client's
//     `styles.insert` global isn't available in the bundle context)
//   - Return shape: { name, inject, apply } (the bundle-plugin client contract)
//
// Tarball: included via the `files` array in package.json. Package version is
// bumped per release.

window.__ModuleLoader__.load({
  id: '@floatingdeaming/minimax-usage',
  factory: (require) => {
    var exports = { exports: {} }.exports
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })

    const react = require('react')
    const useState = react.useState
    const useEffect = react.useEffect
    const useCallback = react.useCallback
    const useRef = react.useRef
    const createElement = react.createElement

    // ---- CSS injection (replaces dynamic-plugin's `styles.insert` global) ----
    let _styleInjected = false
    function injectCSS(css) {
      if (_styleInjected) return
      try {
        const s = document.createElement('style')
        s.setAttribute('data-minx', '1')
        s.textContent = css
        document.head.appendChild(s)
        _styleInjected = true
      } catch (e) {}
    }

    // ---- Helpers (moved from dynamic-plugin client) ----
    function num(x) {
      return (typeof x === 'number' && Number.isFinite(x)) ? x : null
    }
    function clampPct(v) {
      if (v == null || !Number.isFinite(v)) return 0
      if (v < 0) return 0
      if (v > 100) return 100
      return v
    }
    function fmtResetZh(ms) {
      if (ms == null || !Number.isFinite(ms) || ms <= 0) return ''
      let total = Math.ceil(ms / 1000)
      const d = Math.floor(total / 86400)
      total -= d * 86400
      const h = Math.floor(total / 3600)
      total -= h * 3600
      const m = Math.floor(total / 60)
      if (d > 0) return d + ' 天 ' + h + ' 小时后重置'
      return h + ' 小时 ' + m + ' 分钟后重置'
    }
    function fmtTime(iso) {
      if (!iso) return ''
      try {
        const d = new Date(iso)
        if (isNaN(d.getTime())) return ''
        return d.toLocaleString()
      } catch (e) { return '' }
    }
    const COUNT_BASED_MODELS = new Set(['video'])
    function isCountBased(model) {
      const name = model.modelName || ''
      return COUNT_BASED_MODELS.has(name)
    }
    function summarize(model, which) {
      let pct = null, used = null, total = null, resetZh = '', hasData = false
      if (which === '5h') {
        const rp = num(model.remainingPercent5h)
        const up = num(model.usedPercent5h)
        pct = up != null ? up : (rp != null ? (100 - rp) : null)
        used = num(model.used5h)
        total = num(model.total5h)
        resetZh = fmtResetZh(model.resetIn5hMs)
      } else {
        const rp = num(model.remainingPercentWeek)
        const up = num(model.usedPercentWeek)
        pct = up != null ? up : (rp != null ? (100 - rp) : null)
        used = num(model.usedWeek)
        total = num(model.totalWeek)
        resetZh = fmtResetZh(model.resetInWeekMs)
      }
      if (pct != null) pct = clampPct(pct)
      if (isCountBased(model) && pct == null && used != null && total != null && total > 0) {
        pct = clampPct(used / total * 100)
      }
      hasData = pct != null || (used != null && total != null && total > 0)
      return { pct, used, total, resetZh, hasData }
    }
    function pickLabel(model, which, isFirst) {
      const name = model.modelName || 'model'
      if (isFirst) {
        return which === '5h' ? '5h 限额' : '周限额'
      }
      if (name === 'video') return '视频赠送'
      return name + (which === '5h' ? ' 5h' : ' 周')
    }

    // ---- React components ----
    function UsageRow(props) {
      const { label, summary, model } = props
      const useCount = isCountBased(model)
      const w = summary.pct != null ? summary.pct : 0
      const fillStyle = { width: w + '%', minWidth: '4px' }

      const right = (() => {
        if (useCount && summary.used != null && summary.total != null && summary.total > 0) {
          return createElement('div', { className: 'minx-right' },
            createElement('div', { className: 'minx-right-count' },
              createElement('span', { className: 'used' }, String(summary.used)),
              createElement('span', { className: 'sep' }, ' / '),
              createElement('span', { className: 'total' }, String(summary.total)),
              createElement('span', { className: 'y' }, ' 已用')
            )
          )
        }
        if (summary.pct != null) {
          return createElement('div', { className: 'minx-right' },
            createElement('div', { className: 'minx-right-total' }, '总额度 100%'),
            createElement('div', { className: 'minx-right-used' },
              '已用 ', createElement('span', null, Math.round(summary.pct) + '%')
            )
          )
        }
        if (summary.used != null && summary.total != null && summary.total > 0) {
          return createElement('div', { className: 'minx-right' },
            createElement('div', { className: 'minx-right-total' }, '总额度 ' + summary.total),
            createElement('div', { className: 'minx-right-used' },
              '已用 ', createElement('span', null, summary.used)
            )
          )
        }
        return createElement('div', { className: 'minx-right' },
          createElement('div', { className: 'minx-empty' }, '—')
        )
      })()

      return createElement('div', { className: 'minx-row' },
        createElement('div', { className: 'minx-label' },
          createElement('div', { className: 'minx-label-name' },
            createElement('span', { className: 'truncate' }, label)
          ),
          createElement('div', { className: 'minx-label-reset' }, summary.resetZh || '—')
        ),
        createElement('div', { className: 'minx-bar' },
          createElement('div', { className: 'minx-bar-fill', style: fillStyle })
        ),
        right
      )
    }

    function UsageSection(ctx) {
      const { host, interval } = ctx
      const [phase, setPhase] = useState('probing')
      const [state, setState] = useState({ data: null, error: null, lastUpdated: null, cached: false })
      const reqIdRef = useRef(0)
      const refreshRef = useRef(null)

      const refresh = useCallback((opts) => {
        if (refreshRef.current) return refreshRef.current
        const options = opts || {}
        const myId = ++reqIdRef.current
        setState((s) => Object.assign({}, s, { error: null }))
        const p = (async () => {
          try {
            const r = await host.call('minimax.getUsage', options)
            if (myId !== reqIdRef.current) return r
            if (r && r.ok) {
              setState({ data: r, error: null, lastUpdated: r.fetchedAt || new Date().toISOString(), cached: r.cached === true })
              setPhase('ready')
            } else {
              setState((s) => ({ data: s.data || null, error: r || { summary: '查询失败' }, lastUpdated: s.lastUpdated || null, cached: s.cached || false }))
              setPhase('error')
            }
            return r
          } catch (e) {
            if (myId !== reqIdRef.current) return
            setState((s) => ({ data: s.data || null, error: { summary: '请求失败：' + ((e && e.message) || e) }, lastUpdated: s.lastUpdated || null, cached: s.cached || false }))
            setPhase('error')
            return null
          } finally {
            if (myId === reqIdRef.current) refreshRef.current = null
          }
        })()
        refreshRef.current = p
        return p
      }, [])

      useEffect(() => {
        let alive = true
        let auto = null
        ;(async () => {
          try {
            const probe = await host.call('minimax.hasApiKey', {})
            if (!alive) return
            if (probe && probe.ok && probe.hasKey) {
              setPhase('loading')
              safeRefresh({})
            } else {
              setPhase('disabled')
            }
          } catch (e) {
            if (!alive) return
            setPhase('disabled')
          }
        })()

        const safeRefresh = (opts) => { if (alive) { try { refresh(opts); } catch (e) {} } }

        auto = interval(() => safeRefresh({}), 5 * 60 * 1000)

        const onVisible = () => {
          try {
            if (typeof document !== 'undefined' && document.visibilityState === 'visible') {
              safeRefresh({})
            }
          } catch (e) {}
        }
        const onFocus = () => safeRefresh({})
        try {
          if (typeof document !== 'undefined') {
            document.addEventListener('visibilitychange', onVisible)
          }
        } catch (e) {}
        try {
          if (typeof window !== 'undefined') {
            window.addEventListener('focus', onFocus)
          }
        } catch (e) {}

        return () => {
          alive = false
          try { auto(); } catch (e) {}
          try {
            if (typeof document !== 'undefined') {
              document.removeEventListener('visibilitychange', onVisible)
            }
          } catch (e) {}
          try {
            if (typeof window !== 'undefined') {
              window.removeEventListener('focus', onFocus)
            }
          } catch (e) {}
        }
      }, [refresh, interval])

      if (phase === 'probing' || phase === 'disabled') {
        return null
      }

      const r = state.data
      const err = state.error
      const cachedTag = state.cached ? '（缓存）' : ''
      const models = r && Array.isArray(r.models) ? r.models.filter(Boolean) : []

      const header = createElement('div', { className: 'minx-header' },
        createElement('div', { className: 'minx-meta' },
          r ? (r.summary || '') + (state.lastUpdated ? ' · ' + fmtTime(state.lastUpdated) + ' ' + cachedTag : '') : ''
        ),
        createElement('button', {
          className: 'minx-btn',
          disabled: state.error != null,
          onClick: () => { try { refresh({ force: true }); } catch (e) {} }
        }, state.error != null ? '重试' : '刷新')
      )

      if (phase === 'loading' && !r) {
        return createElement('div', { className: 'minx-wrap' },
          header,
          '加载 MiniMax 用量中…'
        )
      }

      if (phase === 'error' && !r) {
        return createElement('div', { className: 'minx-wrap' },
          header,
          createElement('div', { className: 'minx-disabled' },
            '查询失败：' + (err && err.summary || '未知错误'),
            ' · 检查 MINIMAX_API_KEY 是否有效（需要 Token Plan / Subscription Key）'
          )
        )
      }

      if (models.length === 0) {
        return createElement('div', { className: 'minx-wrap' },
          header,
          '未查询到任何模型配额'
        )
      }

      const rowNodes = []
      models.forEach((m, idx) => {
        const isFirst = idx === 0
        const sum5 = summarize(m, '5h')
        const sumW = summarize(m, 'week')
        if (sum5.hasData) {
          rowNodes.push(createElement(UsageRow, {
            key: (m.modelName || 'm') + '-5h-' + idx,
            label: pickLabel(m, '5h', isFirst),
            summary: sum5,
            model: m,
          }))
        }
        if (isFirst && sumW.hasData) {
          rowNodes.push(createElement(UsageRow, {
            key: (m.modelName || 'm') + '-week-' + idx,
            label: pickLabel(m, 'week', isFirst),
            summary: sumW,
            model: m,
          }))
        }
      })

      return createElement('div', { className: 'minx-wrap' },
        header,
        createElement('div', { className: 'minx-card' },
          createElement('div', { className: 'minx-title' }, '套餐用量 · Max Plan'),
          rowNodes
        )
      )
    }

    // ---- The plugin's apply(ctx) — registers the settings section ----
    function apply(ctx) {
      const slots = ctx.slots
      injectCSS(
        '.minx-card{background:transparent;border:1px solid var(--dsw-alias-border-l1);border-radius:10px;padding:12px;margin:0 0 12px;}\n' +
        '.minx-title{font-size:14px;font-weight:600;line-height:1.3;color:var(--dsw-alias-label-primary);margin-bottom:10px;letter-spacing:0.2px;}\n' +
        '.minx-row{display:grid;grid-template-columns:120px minmax(0,1fr) auto;align-items:center;gap:14px;padding:8px 0;}\n' +
        '.minx-row + .minx-row{border-top:1px solid var(--dsw-alias-border-l1);}\n' +
        '.minx-label{min-width:0;line-height:1.25;}\n' +
        '.minx-label-name{font-size:12px;font-weight:500;color:var(--dsw-alias-label-primary);display:flex;align-items:center;gap:4px;}\n' +
        '.minx-label-name .truncate{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}\n' +
        '.minx-label-reset{font-size:11px;color:var(--dsw-alias-label-secondary);margin-top:3px;}\n' +
        '.minx-bar{position:relative;width:100%;height:8px;border-radius:999px;overflow:hidden;background:var(--dsw-alias-bg-layer-2);}\n' +
        '.minx-bar-fill{position:absolute;top:0;bottom:0;left:0;border-radius:999px;background:var(--dsw-alias-state-success-primary);transition:width .35s ease;min-width:4px;}\n' +
        '.minx-right{text-align:right;line-height:1.2;}\n' +
        '.minx-right-total{font-size:13px;font-weight:600;color:var(--dsw-alias-label-primary);}\n' +
        '.minx-right-used{font-size:13px;color:var(--dsw-alias-label-secondary);margin-top:2px;display:flex;align-items:baseline;justify-content:flex-end;gap:4px;}\n' +
        '.minx-right-count{font-size:13px;font-weight:500;color:var(--dsw-alias-label-primary);font-variant-numeric:tabular-nums;display:flex;align-items:baseline;justify-content:flex-end;gap:4px;}\n' +
        '.minx-right-count .used{color:var(--dsw-alias-label-primary);}\n' +
        '.minx-right-count .sep{color:var(--dsw-alias-label-secondary);}\n' +
        '.minx-right-count .total{color:var(--dsw-alias-label-secondary);}\n' +
        '.minx-right-count .y{margin-left:4px;color:var(--dsw-alias-label-secondary);}\n' +
        '.minx-empty{color:var(--dsw-alias-label-secondary);font-size:12px;}\n' +
        '.minx-wrap{margin-top:12px;}\n' +
        '.minx-header{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:4px;}\n' +
        '.minx-meta{font-size:12px;color:var(--dsw-alias-label-secondary);}\n' +
        '.minx-btn{background:transparent;color:var(--dsw-alias-label-primary);border:1px solid var(--dsw-alias-border-l2);border-radius:6px;padding:3px 10px;cursor:pointer;font-size:12px;line-height:1.4;transition:background .15s ease;}\n' +
        '.minx-btn:hover:not([disabled]){background:var(--dsw-alias-bg-layer-2);}\n' +
        '.minx-btn[disabled]{opacity:0.5;cursor:default;}\n' +
        '.minx-disabled{color:var(--dsw-alias-label-secondary);font-size:12px;padding:12px;border:1px dashed var(--dsw-alias-border-l1);border-radius:10px;}\n'
      )
      slots.inject('settings.section', () => slots.register(
        { name: 'settings.section', id: 'minimax-usage', order: 100, label: '用量' },
        UsageSection
      ))
    }

    exports.name = 'minimax-usage-client'
    exports.inject = ['slots', 'timer', 'host', 'interval']
    exports.apply = apply
    return exports
  }
})