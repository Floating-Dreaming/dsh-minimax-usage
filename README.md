# MiniMax 用量插件

> 在 DSH（DeepSeek Harness）设置页「用量」section 展示 MiniMax Token Plan 的 5 小时与周窗口用量。

## 这是什么

DSH 插件，在设置页的「用量」section 渲染 MiniMax Token Plan 实时数据：

- **5 小时窗口**：当前用量百分比 + 剩余时间
- **周窗口**：当前用量百分比 + 重置倒计时
- **视频赠送**：可调用次数（`video` 模型按 count 计，不按百分比）
- **未配置 API key 时整段 section 自动隐藏**（侧栏「用量」入口也不显示）

数据通过 MiniMax 的 `https://www.minimaxi.com/v1/token_plan/remains` 接口实时获取（trusted plugin 持有 key、60s 缓存 + 10s 限流）。

## 安装

| OS | 命令 |
|---|---|
| Windows | `cd D:\Code\minimax-usage-plugin && .\install.ps1` |
| macOS / Linux / WSL / Git Bash | `cd /path/to/minimax-usage-plugin && ./install.sh` |

从 npm 装：

```powershell
.\install.ps1 -Source npm -NpmName @floatingdeaming/minimax-usage
./install.sh --source npm --npm-name @floatingdeaming/minimax-usage
```

脚本做了什么（幂等，已有文件不被覆盖）：

1. 部署 trusted plugin 源码到 `~/.dsh/profiles/web/minimax-usage/`
2. 创建符号链接 `~/.dsh/profiles/web/node_modules/minimax-usage/` → 上面那个目录
3. 校验 / 补齐 profile 的 `package.json` 依赖
4. 校验 / 补齐 profile 的 `pnpm-workspace.yaml` 的 packages 列表
5. 校验 / 补齐 profile 的 `cordis.patch.yml` 的 `- insert:` 行
6. 跑 `npm install`

### 不要用 `dsh plugin add`

虽然 `trusted-plugin/` 声明了 `dsh.bundle` manifest、DSH 的 `dsh plugin add` 命令理论上能认，但**这条路径在你的环境里会留下坏 state**——命令在报错**之前**就已经改写了 `~/.dsh/profiles/web/package.json`，把 npm 风格的 alias `"minimax-usage": "npm:@floatingdeaming/...@^1.0.0"` 改成 pnpm 风格的 `"minimax-usage": "@floatingdeaming/..."`，然后 pnpm add 这一步才挂掉。结果是：

- `package.json` 被改坏，npm alias 失效
- `node_modules/minimax-usage` 变成裸 junction，指向的目录没有 npm 必需的 name-shim `package.json`
- Node 16+ ESM 解析器校验「导入名 ≠ package.json 里的 name」时直接 `ERR_MODULE_NOT_FOUND`

**修复**（手工）：把 `package.json` 改回 npm 风格 alias + 跑 `npm install`。

`install.ps1` / `install.sh` 不走这条路径——直接写文件 + 调 `npm install`，**没有破坏性**。

## 装完之后

1. **重启 DSH**（trusted plugin 必须重启主进程才加载）
2. 配 API key：往 `~/.dsh/.credentials.yaml` 加一行 `MINIMAX_API_KEY: '...'`（**必须是 Token Plan / Subscription key**，不是按量计费的）
3. 新会话里给 agent 发：

   > 请加载并启用 MiniMax 用量插件，依次执行：
   > 1. `cordis_define` 用 `<package-dir>/cordis_define_payload.json` 的完整 JSON 作为参数
   > 2. 拿到返回的 `pluginId` 和 `packageId` 后，`cordis_run` 调 `mode="run"`
   > 3. 如果提示 `awaiting-approval`，请点浏览器顶部的「同意」授权该客户端包

4. **打开设置页 → 用量** section 验证

## 许可证

MIT