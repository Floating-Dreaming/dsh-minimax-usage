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

按提示贴入 `MINIMAX_API_KEY`（**必须用 Token Plan / Subscription Key，不是按量计费的 API Key**）。

绕过交互：

```powershell
# PowerShell
.\install.ps1 -ApiKey 'sk-cp-your-key-here'
.\install.ps1 -SkipKey       # 只部署 trusted plugin，不写 key
.\install.ps1 -Source npm -NpmName @floatingdeaming/minimax-usage   # 从 npm 安装
```

```bash
# bash
./install.sh --key 'sk-cp-your-key-here'
./install.sh --source npm --npm-name @floatingdeaming/minimax-usage
```

脚本做了什么（幂等，已有文件不被覆盖）：

1. 部署 trusted plugin 源码到 `~/.dsh/profiles/web/minimax-usage/`
2. 创建符号链接 `~/.dsh/profiles/web/node_modules/minimax-usage/` → 上面那个目录
3. 校验 / 补齐 profile 的 `package.json` 依赖
4. 校验 / 补齐 profile 的 `pnpm-workspace.yaml` 的 packages 列表
5. 校验 / 补齐 profile 的 `cordis.patch.yml` 的 `- insert:` 行
6. 写 `~/.dsh/.credentials.yaml`（如果给了 key）
7. 跑 `npm install`（默认；pnpm 也会试）

## 装完之后

1. **重启 DSH**（trusted plugin 必须重启主进程才加载）
2. 新会话里给 agent 发：

   > 请加载并启用 MiniMax 用量插件，依次执行：
   > 1. `cordis_define` 用 `<package-dir>/cordis_define_payload.json` 的完整 JSON 作为参数
   > 2. 拿到返回的 `pluginId` 和 `packageId` 后，`cordis_run` 调 `mode="run"`
   > 3. 如果提示 `awaiting-approval`，请点浏览器顶部的「同意」授权该客户端包

3. **打开设置页 → 用量** section 验证

## API key

按以下顺序查找，找到就用：

1. `process.env.MINIMAX_API_KEY`（环境变量）
2. `~/.dsh/.credentials.yaml` 里的 `MINIMAX_API_KEY:` 行（install 脚本默认写这里）

**必须是 Token Plan / Subscription key**，不是按量计费 key。修改后必须重启 DSH 主进程。

## 许可证

MIT