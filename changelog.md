# Changelog — MiniMax 用量插件

## v17 — 当前版本

**改进**：
- Host 新增 `minimax.hasApiKey` JSON 方法（包装 trusted plugin 的 `minimaxUsage.hasApiKey()`）
- Client 挂载时先探测 API key；**没有 key 时整段 section 不渲染**（设置页侧栏也不显示「用量」项）
- 有 key 但调用失败时显示内联提示 + 「重试」按钮（不再弹大片错误）
- Mac / Linux 用户的 `install.sh` 脚本（bash）一并打包

**用户反馈触发**：
> 这个读取的不是 dsh 配置的 minimax 套餐吗？如果没读到，就不展示这个模块哈

**回答**：
- 这个插件**不是读 DSH 配置**——它直接读 MiniMax 服务端的 Token Plan，DSH 没有"minimax 套餐"概念
- 按用户要求，**没读到（无 API key）就不展示**，v17 实现这个行为

## 打包升级 — DSH 官方三件套

**用户反馈**：
> https://deepseek-harness.github.io/deepseek-harness/develop/basic/publish 你看这个插件打包安装教程

**做法**：
1. 读了 `~/.dsh/profiles/web/{cordis.yml, cordis.patch.yml, package.json, pnpm-workspace.yaml}` 和 `node_modules/minimax-usage/`
2. 确认 DSH 官方 plugin 结构 = **npm workspace 包 + 符号链接 + cordis composition patch** 三件套
3. 发现我之前的 `install.ps1` 实际上部署位置是对的（`profiles/web/minimax-usage/`，被 `node_modules/minimax-usage/` 符号链接到），只是没有校验 / 补齐另外两个文件

**install 脚本升级**（不是新版本，是 install 脚本的能力升级）：
- 部署包源码到 `~/.dsh/profiles/web/minimax-usage/index.js`
- 校验 / 创建 `node_modules/minimax-usage/` 符号链接
- 校验 / 补齐 `package.json` 的 `workspace:*` 依赖
- 校验 / 补齐 `pnpm-workspace.yaml` 的 packages 列表
- 校验 / 补齐 `cordis.patch.yml` 的 `- insert:` 行
- 写 API key 到 `~/.dsh/.credentials.yaml`
- 跑 `pnpm install`（如果 pnpm 在 PATH）
- 打印 DSH 重启 + 动态插件加载步骤

`install.ps1` 和 `install.sh` 都按这套升级，是幂等的——已配置好的文件不会被覆盖，只是被检测到。

## v16 — 进度条样式 + 视频 count 化

**改进**：
- 进度条 fill 统一为 `--dsw-alias-state-success-primary` 绿色（5h 和周相同），高度从 7px 提到 8px
- 视频模型（`video`）走 count-based 显示：`0 / 3 已用` 单行格式
- `COUNT_BASED_MODELS` 集合定义哪些模型按次数展示，未来加 `audio` / `image` 等只需扩展该集合
- 视频进度条宽度按 `used5h / total5h` 计算（不是按 0% 的 remainingPercent）

## v15 — 主题 token 化

**改进**：
- 所有颜色从写死的 `rgba(...)` 切到 DSH theme alias token：`--dsw-alias-label-primary` / `--dsw-alias-label-secondary` / `--dsw-alias-border-l1` / `--dsw-alias-bg-layer-2` / `--dsw-alias-state-success-primary` / `--dsw-alias-state-error-primary`
- 卡片背景去掉（透明），边框用 `--dsw-alias-border-l1`
- 顶部 12px margin 移到最外层 `.minx-wrap` 上
- 卡片 padding 统一 12px

**为什么**：跟设置页其它模块（agent preset 卡片等）走同一套 token，亮 / 暗模式自动跟随

## v14 — 样式优化 + 自动刷新

**改进**：
- 字体层次更清晰：标题 600 / label 500 / 重置时间 + 已用走 secondary
- 进度条高度 6px → 7px，圆角 999px
- 新增 `visibilitychange` + `window focus` 自动刷新——切回 DSH 标签页 / 窗口回到前台时自动拉一次
- 配合既有的 5min 定时 + 手动「刷新」按钮，三重保险

## v13 — 横向三列网格

**改进**：
- 从「卡片堆叠」换成 `grid-cols-[120px_minmax(0,1fr)_auto]`
- 第一条 model（`general`）渲染 5h + 周限额两条；其他 model 只渲染一条 5h 行
- 行与行之间用 1px 虚线分割

**背景**：用户给了一段参考 HTML（Tailwind 风格 `bg-ui-card` 等），按那套布局结构复刻

## v12 — 顶部留白

**改进**：卡片 `margin-top` 从 6px 提到 18px，标题上方呼吸空间更明显

## v11 — 聚合逻辑修复

**问题**：v8-v10 用 count 数据聚合，video 模型 count = 3/3 导致进度条按 100% 已用显示

**解决**：
- 聚合改为 `max(100 - remainingPercent)` 跨模型
- 只信 plan-level 的 `remainingPercent*` 字段（API 的 `current_interval_remaining_percent`）
- 忽略 per-model count 数据（不扣 plan 配额）

**结果**：你的数据 5h → 17% / 周 → 26%，跟 expected 一致

## v10 — 重启后调试面板

**触发**：DSH 重启后动态插件 ID 失效，需要重新 `cordis_define`

**作用**：加回 `getDebug` 方法 + 页面下方调试面板，确认 trusted plugin 改动生效

## v9 — Trusted plugin URL 修复（用户手动改）

**改动**：用户改 `C:\Users\yang\.dsh\profiles\web\minimax-usage\index.js`：
- 第 13 行 URL：`/v1/api/openplatform/coding_plan/remains` → `/v1/token_plan/remains`
- `mapModel` 函数增加 `remainingPercent5h` / `remainingPercentWeek` 字段提取

**为什么**：旧端点不返回 `remainingPercent` 字段，导致聚合到 0%

## v8 — 直连新端点（失败回退）

**尝试**：用 `ctx.web.fetch()` + `ctx.credentials.resolve()` 直连 `/v1/token_plan/remains`

**结果**：DSH sandbox 实际上允许 host 通过 `web` 服务发 HTTP，但 credentials 服务没有 `minimax` 这个 ref 的存储，API key 拿不到 → 回退到 trusted plugin 路径

**教训**：host sandbox 实际允许 `web.fetch`，之前以为是禁的；credentials 服务和 trusted plugin 用的存储不一样

## v7 — 数据缺失提示

**改动**：
- 移除调试面板
- 当 `total5h=0` 等数据缺失时显示「— / —」和「数据不完整」副标题
- 卡片底部加提示文字，告知用户 trusted plugin 需要透出百分比字段

## v6 — 页面调试面板

**改进**：debug 日志不再只到 console，直接在页面下方渲染 `<pre>` 块展示 raw + normalized JSON

## v5 — Console.log 诊断

**作用**：在 host 里加一次性 console.log，打印服务原始输出和 host 规范化后的输出

## v4 — 字段回退 + 字段名诊断

**改动**：
- Host 加 `normalizeModel` 做字段名回退（覆盖多种命名风格：snake_case / camelCase / API 原生名）
- Host 加字段计算回退：`used5h = total - remaining` / `usedPercent5h = 100 - remainingPercent`
- 字段名覆盖：`total5h` / `current_interval_total_count` / `intervalTotalCount` 等都尝试

**问题**：用户的 trusted plugin 返回 `used5h: null` / `usedPercent5h: null`，但有 `total5h=0` / `remaining5h=0` / `remainingPercent5h=83`（实际 API 有，只是被服务吞了）

## v3 — 进度条渲染修复

**问题**：`<i>` 作为 inline 元素时 `width: X%` 不生效；`0%` 宽度不可见

**修复**：
- 内层 fill 从 `<i>` 改成 `<div>`
- 显式 `display:block`
- 加 `min-width: 2px` 确保 0% 时仍可见
- 轨道背景从 0.18 提到 0.22

## v2 — 聚合卡片视图

**改进**：从「每个 model 一张卡」改成「套餐用量 · Max Plan」单卡聚合视图
- 标题：套餐用量 · Max Plan
- 5 小时限额 + 周限额两条进度
- 百分比格式：`X% / 100%`
- 重置文案：`< 1 天` → `X小时Y分后重置`，`≥ 1 天` → `X天Y小时后重置`

## v1 — 初始版本

**改动**：从 `D:\Code\token-calculate\minimax-usage-plugin\cordis_define_payload.json` 的初版加载，按每个 model 一张卡渲染

**问题**：用户反馈「样式可以参考这个」+ 提供目标样式描述，触发 v2 重构