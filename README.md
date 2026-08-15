# MiniMax 用量插件

> 在 DSH 设置页「用量」section 展示 MiniMax Token Plan 的 5 小时与周窗口用量（remaining/total/百分比/重置）。
> 当前版本：**v17**（hasApiKey 检测，无 key 不展示）

## 目录

- `cordis_define_payload.json` — 动态插件的 `cordis_define` 参数（含 host + client 源代码），直接在 DSH 会话里喂给 agent 即可
- `trusted-plugin/` — Trusted plugin 源码包，可发布到 npm
  - `index.js` — DSH 主进程跑的 Node 模块（API 调用 + 字段映射 + 缓存）
  - `package.json` — npm 包元数据
  - `README.md` — npm 包说明
  - `.npmignore` — 控制发布内容
- `install.ps1` — Windows 一键部署脚本（支持 `--Source local|npm`）
- `install.sh` — macOS / Linux 一键部署脚本（支持 `--source local|npm`）
- `publish.ps1` — Windows 一键发布脚本（npm publish）
- `publish.sh` — macOS / Linux 一键发布脚本
- `changelog.md` — v1 → v17 的关键决策记录

## 分发路径

| 路径 | 适用场景 | 命令 |
|---|---|---|
| **本地源码部署** | 自己 / 团队内开发测试 | `.\install.ps1`（默认 local 模式） |
| **npm 公开分发** | 跨机器 / 跨团队 / 共享给社区 | 先 `npm publish` 发布 trusted-plugin 包，然后 `.\install.ps1 -Source npm -NpmName @your-scope/dsh-minimax-usage` |

### 发布 trusted plugin 到 npm（开发者侧）

```bash
# 第一次发布：先登录
npm login
cd trusted-plugin
npm publish --access public    # scoped 包必须加 --access public
```

或者用脚本自动 bump version：

```powershell
.\publish.ps1 -Bump patch    # 1.0.0 → 1.0.1
.\publish.ps1 -Bump minor    # 1.0.0 → 1.1.0
.\publish.ps1 -Bump major    # 1.0.0 → 2.0.0
.\publish.ps1 -DryRun        # 只检查不真发
.\publish.ps1 -Tag beta      # 打 beta dist-tag
```

```bash
./publish.sh --bump patch
./publish.sh --bump minor
./publish.sh --bump major
./publish.sh --dry-run
./publish.sh --tag beta
```

发布完成后，得到 `https://www.npmjs.com/package/@dsh-extras/minimax-usage`（或你自定义的 scope / name）。

### 安装者侧（npm 模式）

发布者把 `install.ps1` / `install.sh` 和 `cordis_define_payload.json` 发给用户，用户：

```powershell
# 方式 1：走 npm registry
.\install.ps1 -Source npm -NpmName @your-scope/dsh-minimax-usage -ApiKey 'sk-cp-...'

# 方式 2：默认从 @dsh-extras/minimax-usage 安装
.\install.ps1 -Source npm

# 方式 3：从本地源码安装（不需要 npm 发布）
.\install.ps1
```

```bash
./install.sh --source npm --npm-name @your-scope/dsh-minimax-usage --key 'sk-cp-...'
./install.sh --source npm
./install.sh
```

脚本做的事（npm 模式）：
1. 把 npm 包名加到 DSH profile 的 `package.json` dependencies
2. 跑 `npm install` 把包拉到 `~/.dsh/profiles/web/node_modules/<short-name>/`
3. 校验 `cordis.patch.yml` 有 insert 行
4. 写 API key
5. 打印 DSH 重启 + 动态插件加载步骤

## 跨平台

| OS | 安装脚本 | 运行 | 备注 |
|---|---|---|---|
| Windows | `install.ps1`（PowerShell） | ✅ | 推荐 |
| macOS | `install.sh`（bash） | ✅ | trusted plugin 跑在 Node，无系统差异 |
| Linux | `install.sh`（bash） | ✅ | 同 macOS |
| Windows + WSL / Git Bash | `install.sh`（bash） | ✅ | bash 也行 |

DSH 主进程自身要能在对应平台跑——这个跟插件无关。

## 系统结构

DSH 的 plugin 是 npm workspace 包 + 符号链接 + cordis composition patch 三件套（已验证 `~/.dsh/profiles/web/`）：

```
~/.dsh/profiles/web/                                   ← DSH web profile（受 cordis.yml 装载）
├── minimax-usage/                       ← 包源码（npm workspace 包）
│   ├── package.json                      { name, version, type: "module" }
│   └── index.js                          export { apply, name, inject }
├── node_modules/minimax-usage/           ← pnpm 符号链接 → ../minimax-usage/
├── package.json                          ← 依赖 "minimax-usage": "workspace:*"
├── pnpm-workspace.yaml                   ← packages: [., minimax-usage]
└── cordis.patch.yml                      ← - insert: [{ id: minimax-usage, name: minimax-usage }]
```

加载时机：

```
DSH 主进程 (Node)                          DSH 浏览器 (React)
┌────────────────────────────┐            ┌────────────────────────────┐
│  trusted plugin (trusted)  │            │  dynamic plugin (client)   │
│  ┌──────────────────────┐  │  inject    │  ┌──────────────────────┐  │
│  │ minimaxUsage         │◀─┼──────────┼──┤ minimax.getUsage     │  │
│  │   .getUsage()        │  │   JSON    │  │   host.call(...)      │  │
│  │   .hasApiKey()       │  │   RPC    │  │                        │  │
│  └──────────────────────┘  │            │  │ minimax.hasApiKey     │  │
│           │                │            │  │   host.call(...)      │  │
│           ▼                │            │  └──────────────────────┘  │
│  ┌──────────────────────┐  │            │            │                │
│  │ httpsGet             │  │            │            ▼                │
│  │  /v1/token_plan/     │  │            │   settings.section slot   │
│  │       remains        │  │            │   (用量)                   │
│  └──────────────────────┘  │            │                            │
└────────────────────────────┘            └────────────────────────────┘
```

**trusted plugin**（npm 包）持有 API key、发起 HTTP 请求、做 60s 内存缓存 + 10s 限流
**dynamic plugin (host)** 把 `minimaxUsage` 服务通过 JSON RPC 暴露给浏览器，提供 `getUsage` + `hasApiKey`；做字段名规范化
**dynamic plugin (client)** 渲染设置页的「用量」section（每次新 DSH 会话通过 `cordis_define` 加载）

## 显示行为

| 场景 | 显示 |
|---|---|
| 有 API key + 数据正常 | 「套餐用量 · Max Plan」卡片，含 5h 限额 + 周限额 + 视频赠送行 |
| 有 API key + 数据为空 | 「未查询到任何模型配额」 |
| 有 API key + 网络/API 错误 | 内联「查询失败：...」提示（带「重试」按钮） |
| **没 API key / trusted plugin 未配置** | **整段 section 完全不渲染**（设置页侧栏也不显示「用量」项） |

`hasApiKey()` 在挂载时调一次；后续不再每次检查。配置好 key 并重启 DSH 后，下次会话启用插件即生效。

## 部署步骤

### Windows

```powershell
cd D:\Code\tools-plugin\minimax-usage-plugin
.\install.ps1
```

按提示贴入 `MINIMAX_API_KEY`（**必须用 Token Plan / Subscription Key，不是按量计费的 API Key**），脚本会：
1. 复制 `trusted-plugin\index.js` → `~/.dsh/profiles/web/minimax-usage/index.js`
2. 创建符号链接 `~/.dsh/profiles/web/node_modules/minimax-usage/` → 上面那个目录
3. 校验 `package.json` 有 `"minimax-usage": "workspace:*"` 依赖（没有就补）
4. 校验 `pnpm-workspace.yaml` 列出 `minimax-usage` 包（没有就补）
5. 校验 `cordis.patch.yml` 有 `- insert: [id: minimax-usage, name: minimax-usage]`（没有就补）
6. 写 `~/.dsh/.credentials.yaml`（如果给了 key）
7. 跑 `pnpm install`（如果 pnpm 在 PATH 上）
8. 打印后续 DSH 会话里要执行的 `cordis_define` / `cordis_run` 步骤

绕过交互：
```powershell
.\install.ps1 -ApiKey 'sk-cp-your-key-here'
.\install.ps1 -SkipKey      # 只部署 trusted plugin，不写 key
```

### macOS / Linux（Windows + Git Bash / WSL 也行）

```bash
cd /path/to/minimax-usage-plugin
./install.sh
```

或绕过交互：
```bash
./install.sh --key 'sk-cp-your-key-here'
./install.sh --dsh-home ~/.dsh --skip-key   # 只部署，不写 key
```

脚本会做跟 Windows 版同样的 8 步流程。

### 通用后续步骤

1. **重启 DSH**（trusted plugin 必须重启主进程才加载）
2. 新会话里，把这段发给 agent：

> 请加载并启用 MiniMax 用量插件，依次执行：
> 1. cordis_define 用 `<package-dir>/cordis_define_payload.json` 的完整 JSON 作为参数（plugin / name / purpose / code 四个字段都在里面）
> 2. 拿到返回的 pluginId 和 packageId 后，cordis_run 调 mode="run"
> 3. 如果提示 awaiting-approval，请点浏览器顶部的「同意」授权该客户端包

3. **打开设置页 → 用量** 验证：
   ```
   套餐用量 · Max Plan
   ┌──────────────────────────────────────────┐
   │ 5h 限额              ▓▓▓░░░░░░░░░░   总额度 100%  │
   │ 2 小时 30 分钟后重置                       已用 21%   │
   ├──────────────────────────────────────────┤
   │ 周限额              ▓▓▓▓▓░░░░░░░░   总额度 100%  │
   │ 1 天 2 小时后重置                          已用 26%   │
   ├──────────────────────────────────────────┤
   │ 视频赠送            ░░░░░░░░░░░░░░   0 / 3 已用 │
   │ 2 小时 30 分钟后重置                                  │
   └──────────────────────────────────────────┘
   ```

如果**没看到这个 section**，说明 `MINIMAX_API_KEY` 没配好 / trusted plugin 没部署——回到第 1 步重新检查。

## API key 在哪配置

按以下顺序查找，找到就用：

1. `process.env.MINIMAX_API_KEY`（环境变量）
2. `~/.dsh/.credentials.yaml` 里的 `MINIMAX_API_KEY:` 行（推荐，install 脚本默认写这里）
3. （不会）fallback

修改后**必须重启 DSH 主进程**才会重新加载。

## 卸载

```bash
# 删 trusted plugin
rm -rf ~/.dsh/profiles/web/minimax-usage
# PowerShell: Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\profiles\web\minimax-usage"

# 清 API key
# 手动编辑 ~/.dsh/.credentials.yaml 删掉 MINIMAX_API_KEY 行

# 重启 DSH

# 动态插件在下次会话结束时自动消失
```

## 升级

1. 修改 `trusted-plugin/index.js`（如果改 URL / 重试 / 缓存策略）
2. 修改 `cordis_define_payload.json`（如果改 UI / 聚合逻辑）
3. 重跑 `install.ps1` 或 `install.sh`（会覆盖 trusted plugin 文件）
4. 重启 DSH
5. 新会话里 `cordis_run` 切到新 `packageId`

## 已知限制 / 注意事项

- **trusted plugin 必须重启 DSH 才会加载**——它跑在主进程，不在 sandbox 里
- **dynamic plugin 不跨会话持久化**——DSH 设计如此，每个新会话要重新 `cordis_define` + `cordis_run`
- **API 限流**：trusted plugin 内置 10s/req 限流 + 60s 内存缓存，前端 5min 自动刷新 + visibility/focus 自动刷新，不会打爆 MiniMax
- **绑定到 Token Plan Key**（不是按量计费 key），用错会返回 `1004: 请检查 MINIMAX_API_KEY`
- **本插件是只读视图**，不修改任何 DSH 状态、不执行 DSH 命令、不读 DSH 设置——只是拿 MiniMax API key 去 MiniMax 服务端问数据
- 视频（`video` 模型）按次数算，不按百分比——client 代码里 `COUNT_BASED_MODELS` 集合定义了哪些走 count 展示

## 文件用途速查

| 文件 | 何时被加载 |
|---|---|
| `trusted-plugin/index.js` | DSH 主进程启动时，被 profiles 扫描加载 |
| `cordis_define_payload.json` | DSH 会话内，agent 收到你的指令后调用 `cordis_define` 时 |
| `install.ps1` / `install.sh` | 你手动运行，部署 trusted plugin + API key |