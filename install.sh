#!/usr/bin/env bash
# install.sh — MiniMax 用量插件一键部署脚本（macOS / Linux）
#
# Windows 上请用 install.ps1，或在 Git Bash / WSL 里跑这个脚本
#
# DSH 官方 plugin 结构（已验证 ~/.dsh/profiles/web/node_modules/minimax-usage/index.js）：
#
#   ~/.dsh/profiles/web/
#   ├── minimax-usage/                       ← 包源码（本脚本部署到这里，npm 模式跳过）
#   │   └── index.js
#   ├── node_modules/minimax-usage/           ← pnpm workspace 符号链接 → ../minimax-usage/
#   ├── package.json                          ← 依赖 "minimax-usage": "workspace:*"
#   ├── pnpm-workspace.yaml                   ← packages: [., minimax-usage]
#   └── cordis.patch.yml                      ← - insert: [{ id: minimax-usage, name: minimax-usage }]
#
# 用法：
#   ./install.sh                                       # 本地源码模式
#   ./install.sh --source npm --npm-name @you/pkg      # npm 模式
#   ./install.sh --key 'sk-cp-...'                     # 直接传 key
#   ./install.sh --dsh-home ~/custom                   # 自定义 DSH home
#   ./install.sh --skip-key                            # 只部署 trusted plugin，不配置 key

set -euo pipefail

SOURCE="local"
NPM_NAME="@floatingdeaming/minimax-usage"
API_KEY=""
DSH_HOME=""
SKIP_KEY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)    SOURCE="$2"; shift 2 ;;
    --npm-name)  NPM_NAME="$2"; shift 2 ;;
    --key)       API_KEY="$2"; shift 2 ;;
    --dsh-home)  DSH_HOME="$2"; shift 2 ;;
    --skip-key)  SKIP_KEY=1; shift ;;
    -h|--help)
      sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ "$SOURCE" != "local" && "$SOURCE" != "npm" ]]; then
  echo "Invalid --source: $SOURCE (must be 'local' or 'npm')" >&2
  exit 1
fi

# ---- 0. Resolve DSH home ---------------------------------------------------
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE_DIR="$DSH_HOME/profiles/web"
echo "DSH home: $DSH_HOME"
echo "Profile dir: $PROFILE_DIR"
echo "Source: $SOURCE"

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "DSH web profile not found at $PROFILE_DIR. Install DSH first." >&2
  exit 1
fi

# ---- 1. Deploy trusted plugin ---------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$PROFILE_DIR/minimax-usage"
NODE_MODULES_LINK="$PROFILE_DIR/node_modules/minimax-usage"

case "$SOURCE" in
  local)
    PLUGIN_SRC="$SCRIPT_DIR/trusted-plugin/index.js"
    if [[ ! -f "$PLUGIN_SRC" ]]; then
      echo "Trusted plugin source not found: $PLUGIN_SRC" >&2
      exit 1
    fi
    mkdir -p "$PACKAGE_DIR"
    cp -f "$PLUGIN_SRC" "$PACKAGE_DIR/index.js"
    echo "Deployed local source -> $PACKAGE_DIR/index.js"
    ;;
  npm)
    echo "Will install $NPM_NAME from npm in the DSH profile..."
    PROFILE_PKG="$PROFILE_DIR/package.json"
    if [[ ! -f "$PROFILE_PKG" ]]; then
      echo "$PROFILE_PKG not found" >&2
      exit 1
    fi
    node -e "
      const fs = require('fs');
      const p = JSON.parse(fs.readFileSync('$PROFILE_PKG','utf8'));
      p.dependencies = p.dependencies || {};
      const shortName = '$NPM_NAME'.split('/').pop();
      p.dependencies[shortName] = '$NPM_NAME';
      fs.writeFileSync('$PROFILE_PKG', JSON.stringify(p, null, 2) + '\n');
    "
    echo "Added $NPM_NAME to $PROFILE_PKG dependencies"
    ;;
esac

# Verify or create the node_modules symlink (local mode only)
if [[ "$SOURCE" == "local" ]]; then
  if [[ -e "$NODE_MODULES_LINK" || -L "$NODE_MODULES_LINK" ]]; then
    if [[ -L "$NODE_MODULES_LINK" ]]; then
      echo "Workspace link exists: $NODE_MODULES_LINK -> $(readlink "$NODE_MODULES_LINK")"
    else
      echo "WARNING: $NODE_MODULES_LINK exists but is not a symlink." >&2
    fi
  else
    mkdir -p "$PROFILE_DIR/node_modules"
    ln -s "$PACKAGE_DIR" "$NODE_MODULES_LINK"
    echo "Created symlink: $NODE_MODULES_LINK -> $PACKAGE_DIR"
  fi
fi

# ---- 2. Run npm/pnpm install ---------------------------------------------
if [[ "$SOURCE" == "npm" ]]; then
  if command -v npm >/dev/null 2>&1; then
    echo "Running npm install in $PROFILE_DIR ..."
    (cd "$PROFILE_DIR" && npm install) || echo "npm install failed; DSH may not load the plugin correctly." >&2
  else
    echo "npm not on PATH — install it and run 'npm install' in $PROFILE_DIR manually" >&2
  fi
else
  if command -v pnpm >/dev/null 2>&1; then
    echo "Running pnpm install in $PROFILE_DIR ..."
    (cd "$PROFILE_DIR" && pnpm install) || echo "pnpm install failed; DSH may not load the plugin correctly." >&2
  else
    echo "pnpm not on PATH — skipping install. If DSH fails to load, run 'pnpm install' in $PROFILE_DIR" >&2
  fi
fi

# ---- 3. Verify / patch profile package.json -------------------------------
PROFILE_PKG="$PROFILE_DIR/package.json"
if [[ -f "$PROFILE_PKG" ]]; then
  if [[ "$SOURCE" == "local" ]]; then
    if ! grep -q '"minimax-usage"' "$PROFILE_PKG"; then
      TMP="$(mktemp)"
      node -e "
        const fs = require('fs');
        const p = JSON.parse(fs.readFileSync('$PROFILE_PKG','utf8'));
        p.dependencies = p.dependencies || {};
        if (!p.dependencies['minimax-usage']) p.dependencies['minimax-usage'] = 'workspace:*';
        fs.writeFileSync('$TMP', JSON.stringify(p, null, 2) + '\n');
      "
      mv "$TMP" "$PROFILE_PKG"
      echo "Added workspace:* dependency to $PROFILE_PKG"
    else
      echo "package.json already has minimax-usage dependency"
    fi
  else
    echo "package.json has $NPM_NAME (added in step 1)"
  fi
fi

# ---- 4. Verify / patch pnpm-workspace.yaml --------------------------------
if [[ "$SOURCE" == "local" ]]; then
  WORKSPACE_YAML="$PROFILE_DIR/pnpm-workspace.yaml"
  if [[ -f "$WORKSPACE_YAML" ]]; then
    if ! grep -q 'minimax-usage' "$WORKSPACE_YAML"; then
      if grep -q '^packages:' "$WORKSPACE_YAML"; then
        awk '
          /^packages:/ { print; print "  - minimax-usage"; in_pkg=1; next }
          in_pkg && /^[[:space:]]*-/ { next }
          in_pkg && /^[[:space:]]*[a-z]/ && !/^[[:space:]]*-/ { in_pkg=0 }
          { print }
        ' "$WORKSPACE_YAML" > "$WORKSPACE_YAML.tmp"
        mv "$WORKSPACE_YAML.tmp" "$WORKSPACE_YAML"
      else
        printf '\npackages:\n  - .\n  - minimax-usage\n' >> "$WORKSPACE_YAML"
      fi
      echo "Added minimax-usage to $WORKSPACE_YAML"
    else
      echo "pnpm-workspace.yaml already lists minimax-usage"
    fi
  fi
fi

# ---- 5. Verify / patch cordis.patch.yml ------------------------------------
PATCH_YAML="$PROFILE_DIR/cordis.patch.yml"
if [[ -f "$PATCH_YAML" ]]; then
  if ! grep -qE '^[[:space:]]*-[[:space:]]*id:[[:space:]]*minimax-usage' "$PATCH_YAML"; then
    cat >> "$PATCH_YAML" <<'EOF'

# Trusted MiniMax usage plugin: registers the minimaxUsage service
- insert:
    - id: minimax-usage
      name: minimax-usage
EOF
    echo "Added insert row to $PATCH_YAML"
  else
    echo "cordis.patch.yml already has minimax-usage insert"
  fi
fi

# ---- 6. Configure API key --------------------------------------------------
RESOLVED_KEY=""
if [[ $SKIP_KEY -eq 0 ]]; then
  if [[ -n "$API_KEY" ]]; then
    RESOLVED_KEY="$API_KEY"
  elif [[ -n "${MINIMAX_API_KEY:-}" ]]; then
    RESOLVED_KEY="$MINIMAX_API_KEY"
    echo "Using existing MINIMAX_API_KEY environment variable."
  fi

  if [[ -z "$RESOLVED_KEY" ]]; then
    echo ""
    echo "MINIMAX_API_KEY is not set."
    echo "Get your Token Plan key from https://www.minimaxi.com/ (NOT the metered-billing key)."
    echo ""
    read -rs -p "Paste your MINIMAX_API_KEY (input hidden): " RESOLVED_KEY
    echo ""
    if [[ -z "$RESOLVED_KEY" ]]; then
      read -p "Paste your MINIMAX_API_KEY (visible): " RESOLVED_KEY
    fi
  fi

  if [[ -n "$RESOLVED_KEY" ]]; then
    CRED_FILE="$DSH_HOME/.credentials.yaml"
    ESCAPED_KEY="${RESOLVED_KEY//\'/\'\'}"
    KEY_LINE="MINIMAX_API_KEY: '${ESCAPED_KEY}'"

    if [[ -f "$CRED_FILE" ]]; then
      if grep -qE '^[[:space:]]*MINIMAX_API_KEY[[:space:]]*:' "$CRED_FILE"; then
        TMP_FILE="$(mktemp)"
        sed -E "s|^[[:space:]]*MINIMAX_API_KEY[[:space:]]*:.*$|${KEY_LINE//|/\\|}|" "$CRED_FILE" > "$TMP_FILE"
        mv "$TMP_FILE" "$CRED_FILE"
      else
        if [[ -s "$CRED_FILE" ]] && [[ "$(tail -c 1 "$CRED_FILE" | wc -l)" -eq 0 ]]; then
          echo "" >> "$CRED_FILE"
        fi
        echo "$KEY_LINE" >> "$CRED_FILE"
      fi
    else
      mkdir -p "$DSH_HOME"
      echo "$KEY_LINE" > "$CRED_FILE"
    fi
    echo "Wrote MINIMAX_API_KEY to $CRED_FILE"
  fi
fi

# ---- 7. Summary and next-step instructions --------------------------------
if [[ -n "$RESOLVED_KEY" ]]; then
  echo ""
  echo -e "\033[32mAPI key configured.\033[0m Sanity check:"
  echo "  Length: ${#RESOLVED_KEY}"
  PREFIX="${RESOLVED_KEY:0:7}"
  echo "  Prefix: ${PREFIX}..."
else
  echo ""
  echo -e "\033[33mWARNING:\033[0m no API key was set. Plugin will return 'missing_key' until you"
  echo "         add MINIMAX_API_KEY to env or to $DSH_HOME/.credentials.yaml"
fi

echo ""
echo -e "\033[36m=== NEXT STEPS ===\033[0m"
echo ""
echo "1. RESTART DSH (the trusted plugin only loads at main-process startup):"
echo "   - Quit the DSH desktop window completely"
echo "   - Reopen DSH"
echo ""
echo "2. In a new DSH session, send this message to the agent:"
echo ""
echo '   请加载并启用 MiniMax 用量插件，依次执行：'
echo '   1) cordis_define 用 '"$SCRIPT_DIR"'/cordis_define_payload.json'
echo '      的完整 JSON 作为参数（plugin / name / purpose / code 四个字段都在里面）'
echo '   2) 拿到返回的 pluginId 和 packageId 后，cordis_run 调 mode="run"'
echo '   3) 如果提示 awaiting-approval，请点浏览器顶部的「同意」授权该客户端包'
echo ""
echo "   The plugin will mount a \"用量\" section in Settings."
echo ""
echo "3. Open Settings page → \"用量\" section to see the cards."
echo ""