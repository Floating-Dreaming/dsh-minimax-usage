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

两种方式，**任选其一**。

### 方式一：DSH 官方 `dsh plugin add`

`trusted-plugin/` 声明了 `dsh.bundle` manifest，DSH 官方安装命令直接认：

```sh
# 从 GitHub（git 源一行）
dsh plugin --profile web add "github:Floating-Dreaming/dsh-minimax-usage#main"

# 从 npm
dsh plugin --profile web add @floatingdeaming/minimax-usage

# 从本地 checkout
dsh plugin --profile web add ./trusted-plugin
```

装完**重启 DSH**。

### 方式二：`install.ps1` / `install.sh`

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

## 许可证

MIT