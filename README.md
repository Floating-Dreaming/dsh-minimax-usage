# MiniMax 用量插件

> 在 DSH（DeepSeek Harness）设置页「用量」section 展示 MiniMax Token Plan 的 5 小时与周窗口用量。
> 当前版本：**v17**（hasApiKey 检测，无 key 不展示）

![结构示意图](docs/structure.svg)

## 这是什么

一个 DSH 插件，分为两部分：

| 部分 | 跑在哪 | 做什么 |
|---|---|---|
| **trusted plugin**（npm 包） | DSH 主进程（Node） | 持有 MiniMax API key、调 `/v1/token_plan/remains`、做 60s 缓存 + 10s 限流 + 字段映射 |
| **dynamic plugin**（每次会话加载） | DSH 浏览器（React） | 在设置页「用量」section 渲染进度条卡片，没配 key 时不显示 |

两者通过 DSH 的 Host ↔ Client JSON RPC 通信：浏览器端 `host.call('minimax.getUsage', {})` → 主进程 `minimaxUsage.getUsage()` → HTTP → 返回结构化数据 → 渲染。

## 系统结构

DSH 的插件采用 npm workspace 包 + 符号链接 + cordis composition patch 三件套（已验证 `~/.dsh/profiles/web/`）：

```
~/.dsh/profiles/web/                                   ← DSH web profile
├── minimax-usage/                       ← 包源码（npm workspace 包）
│   ├── package.json                      { name, version, type: "module" }
│   └── index.js                          export { apply, name, inject }
├── node_modules/minimax-usage/           ← pnpm 符号链接 → ../minimax-usage/
├── package.json                          ← 依赖 "minimax-usage": "workspace:*"
├── pnpm-workspace.yaml                   ← packages: [., minimax-usage]
└── cordis.patch.yml                      ← - insert: [{ id: minimax-usage, name: minimax-usage }]
```

加载后的运行时架构：

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

**trusted plugin** 持有 API key、发起 HTTP 请求、做 60s 内存缓存 + 10s 限流
**dynamic plugin (host)** 把 `minimaxUsage` 服务通过 JSON RPC 暴露给浏览器；做字段名规范化
**dynamic plugin (client)** 渲染设置页的「用量」section（每次新 DSH 会话通过 `cordis_define` 加载）

## 显示效果

| 场景 | 显示 |
|---|---|
| 有 API key + 数据正常 | 「套餐用量 · Max Plan」卡片：5h 限额 + 周限额 + 视频赠送 |
| 有 API key + 数据为空 | 「未查询到任何模型配额」 |
| 有 API key + 网络/API 错误 | 内联「查询失败：...」+ 「重试」按钮 |
| **没 API key / trusted plugin 未配置** | **整段 section 完全不渲染**（设置页侧栏也不显示「用量」项） |

`hasApiKey()` 在挂载时调一次；后续不再每次检查。配置好 key 并重启 DSH 后，下次会话启用插件即生效。

### 正常显示示例

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

## 部署

### Windows

```powershell
cd D:\Code\minimax-usage-plugin
.\install.ps1
```

按提示贴入 `MINIMAX_API_KEY`（**必须用 Token Plan / Subscription Key，不是按量计费的 API Key**）。

绕过交互：

```powershell
.\install.ps1 -ApiKey 'sk-cp-your-key-here'
.\install.ps1 -SkipKey      # 只部署 trusted plugin，不写 key
.\install.ps1 -Source npm -NpmName @floatingdeaming/minimax-usage   # 从 npm 安装
```

### macOS / Linux（Windows + Git Bash / WSL 也行）

```bash
cd /path/to/minimax-usage-plugin
./install.sh
./install.sh --key 'sk-cp-your-key-here'
./install.sh --source npm --npm-name @floatingdeaming/minimax-usage
```

### install 脚本做的事（幂等）

1. 部署 `trusted-plugin/index.js` 到 `~/.dsh/profiles/web/minimax-usage/`
2. 创建符号链接 `~/.dsh/profiles/web/node_modules/minimax-usage/` → 上面那个目录
3. 校验 / 补齐 `package.json` 的 `"minimax-usage": "workspace:*"` 依赖
4. 校验 / 补齐 `pnpm-workspace.yaml` 的 packages 列表
5. 校验 / 补齐 `cordis.patch.yml` 的 `- insert:` 行
6. 写 `~/.dsh/.credentials.yaml`（如果给了 key）
7. 跑 `pnpm install`（如果 pnpm 在 PATH 上）
8. 打印 DSH 重启 + 动态插件加载步骤

### 部署后

1. **重启 DSH**（trusted plugin 必须重启主进程才加载）
2. 新会话里给 agent 发：

> 请加载并启用 MiniMax 用量插件，依次执行：
> 1. cordis_define 用 `<package-dir>/cordis_define_payload.json` 的完整 JSON 作为参数（plugin / name / purpose / code 四个字段都在里面）
> 2. 拿到返回的 pluginId 和 packageId 后，cordis_run 调 mode="run"
> 3. 如果提示 awaiting-approval，请点浏览器顶部的「同意」授权该客户端包

3. **打开设置页 → 用量** 验证。

## API key 配置

按以下顺序查找，找到就用：

1. `process.env.MINIMAX_API_KEY`（环境变量）
2. `~/.dsh/.credentials.yaml` 里的 `MINIMAX_API_KEY:` 行（推荐，install 脚本默认写这里）

**必须是 Token Plan / Subscription key**，不是按量计费 key。修改后必须重启 DSH 主进程。

如果用的是按量计费的 key，会返回 `1004: 请检查 MINIMAX_API_KEY（需要 MiniMax Token Plan/Subscription Key，不是按量计费 API Key）`。

## 跨平台

| OS | install 脚本 | 运行 | 备注 |
|---|---|---|---|
| Windows | `install.ps1`（PowerShell） | ✅ | 推荐 |
| macOS | `install.sh`（bash） | ✅ | trusted plugin 跑在 Node，无系统差异 |
| Linux | `install.sh`（bash） | ✅ | 同 macOS |
| Windows + WSL / Git Bash | `install.sh`（bash） | ✅ | bash 也行 |

DSH 主进程自身要能在对应平台跑——这个跟插件无关。

## 分发路径

| 路径 | 适用场景 | 操作 |
|---|---|---|
| **本地源码部署** | 自己 / 团队内开发测试 | `.\install.ps1`（默认 local 模式） |
| **npm 公开分发** | 跨机器 / 跨团队 / 共享给社区 | 先 `npm publish` 发布 trusted-plugin 包，然后 `.\install.ps1 -Source npm -NpmName @floatingdeaming/minimax-usage` |
| **GitHub 公开** | 代码开源 / 版本管理 / 社区贡献 | 在 GitHub 建仓库并 push，然后 `git tag v1.0.0 && git push --tags` 触发 GitHub Actions 自动发 npm |

### 发布 trusted plugin 到 npm

```bash
cd trusted-plugin
npm login
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

发布完成后，得到 `https://www.npmjs.com/package/@floatingdeaming/minimax-usage`（或你自定义的 scope / name）。

### 推送到 GitHub

`publish-to-github.ps1` 一站式脚本（你需要在本机 PowerShell 跑，不在 sandbox 里）：

```powershell
cd D:\Code\minimax-usage-plugin
.\publish-to-github.ps1
```

会一次性做完：
- 用 gh 取 OAuth token（如果 gh.exe 不在 PATH 会自动定位 `C:\Program Files\GitHub CLI\gh.exe`）
- 推 `main` 分支（embedded-token URL，push 完立刻清掉）
- 改 GitHub default branch + 删 `feat/initial-commit`
- 用 `gh api` 配 main 分支的 branch protection
- 给仓加 `dsh-plugin` 等 topics

## 注册到 DSH 插件生态

DSH 插件市场有几条主要路径：

| 路径 | URL | 操作 | 状态 |
|---|---|---|---|
| **GitHub 仓** | https://github.com/Floating-Dreaming/dsh-minimax-usage | `git push` + branch protection | ✅ 已发布 |
| **npm 包** | https://www.npmjs.com/package/@floatingdeaming/minimax-usage | `npm publish --access public` | ✅ v1.0.0 已发布 |
| **awesome-dsh-plugin** | https://github.com/awesome-dsh-plugin/awesome-dsh-plugin | 开 PR 加到 UI Enhancements | ✅ [PR #632](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin/pull/632) 待合并 |
| **vlln/plugin-registry** | https://github.com/vlln/plugin-registry | ⚠️ 不是插件目录；它是「薄控制台 + make-dsh-plugin skill」基础设施仓，没有插件收录流程 | 跳过 |
| **HubaKing/dsh-community-plugins** | https://github.com/HubaKing/dsh-community-plugins | 装这个 skill 进 DSH，里面介绍所有市场 | 可选 |

awesome-dsh-plugin 维护方会跑 `dsh-plugin-doctor` 之类的检查；本插件用的是 trusted-plugin + dynamic-client 架构（API key 必须留在主进程），没有 `dsh.bundle` manifest，已在 PR body 里说明。

## 数据来源说明

**这个插件不是读 DSH 配置**——它直接读 MiniMax 服务端的 Token Plan 状态：

- DSH 没有"minimax 套餐"概念
- 插件拿用户的 `MINIMAX_API_KEY` 去 MiniMax `/v1/token_plan/remains` 端点查
- 显示的"套餐"是 MiniMax 那边绑在那把 key 上的 Token Plan 实时数据
- **本插件是只读视图**，不修改任何 DSH 状态、不执行 DSH 命令、不读 DSH 设置

## 升级

1. 修改 `trusted-plugin/index.js`（如果改 URL / 重试 / 缓存策略）
2. 修改 `cordis_define_payload.json`（如果改 UI / 聚合逻辑）
3. 重跑 `install.ps1` 或 `install.sh`（会覆盖 trusted plugin 文件）
4. 重启 DSH
5. 新会话里 `cordis_run` 切到新 `packageId`

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

## 已知限制 / 注意事项

- **trusted plugin 必须重启 DSH 才会加载**——它跑在主进程，不在 sandbox 里
- **dynamic plugin 不跨会话持久化**——DSH 设计如此，每个新会话要重新 `cordis_define` + `cordis_run`
- **API 限流**：trusted plugin 内置 10s/req 限流 + 60s 内存缓存，前端 5min 自动刷新 + visibility/focus 自动刷新，不会打爆 MiniMax
- **绑定到 Token Plan Key**（不是按量计费 key），用错会返回 `1004: 请检查 MINIMAX_API_KEY`
- **本插件是只读视图**，不修改任何 DSH 状态、不执行 DSH 命令、不读 DSH 设置
- 视频（`video` 模型）按次数算，不按百分比——client 代码里 `COUNT_BASED_MODELS` 集合定义了哪些走 count 展示

## 文件用途速查

| 文件 | 何时被加载 |
|---|---|
| `trusted-plugin/index.js` | DSH 主进程启动时，被 profiles 扫描加载 |
| `cordis_define_payload.json` | DSH 会话内，agent 收到你的指令后调用 `cordis_define` 时 |
| `install.ps1` / `install.sh` | 你手动运行，部署 trusted plugin + API key |
| `publish.ps1` / `publish.sh` | 开发者运行，发 npm |
| `publish-to-github.ps1` | 开发者运行，推 GitHub + 开 PR |
| `changelog.md` | v1 → v17 的关键决策记录 |

## 许可证

MIT