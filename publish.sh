#!/usr/bin/env bash
# publish.sh — publish the trusted plugin to npm registry (macOS / Linux)
#
# Windows 上请用 publish.ps1
#
# 用法：
#   ./publish.sh                          # 用 package.json 里的当前 version
#   ./publish.sh --bump patch             # patch bump (1.0.0 → 1.0.1)
#   ./publish.sh --bump minor             # minor bump (1.0.0 → 1.1.0)
#   ./publish.sh --bump major             # major bump (1.0.0 → 2.0.0)
#   ./publish.sh --dry-run               # 不真发布，只检查
#   ./publish.sh --tag beta               # 打 tag beta + @beta dist-tag
#
# 前提：先 `npm login` 或 `npm adduser` 登录 npmjs.org

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/trusted-plugin"
PKG_JSON="$PLUGIN_DIR/package.json"

if [[ ! -f "$PKG_JSON" ]]; then
  echo "package.json not found at $PKG_JSON" >&2
  exit 1
fi

BUMP="none"
DRY_RUN=0
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)    BUMP="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --tag)     TAG="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ---- 1. Read current version ----------------------------------------------
NAME=$(node -p "require('$PKG_JSON').name")
OLD_VERSION=$(node -p "require('$PKG_JSON').version")
echo "Package: $NAME"
echo "Current version: $OLD_VERSION"

# ---- 2. Bump version if requested ------------------------------------------
bump_version() {
  local v="$1" kind="$2"
  if [[ "$kind" == "none" ]]; then echo "$v"; return; fi
  IFS='.' read -r major minor patch <<< "$v"
  case "$kind" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac
  echo "$major.$minor.$patch"
}

NEW_VERSION=$(bump_version "$OLD_VERSION" "$BUMP")
if [[ "$NEW_VERSION" != "$OLD_VERSION" ]]; then
  node -e "
    const fs = require('fs');
    const p = JSON.parse(fs.readFileSync('$PKG_JSON', 'utf8'));
    p.version = '$NEW_VERSION';
    fs.writeFileSync('$PKG_JSON', JSON.stringify(p, null, 2) + '\n');
  "
  echo "Bumped to: $NEW_VERSION"
else
  echo "No version bump"
fi

# ---- 3. Sanity checks ------------------------------------------------------
if [[ ! "$NAME" =~ ^@?[a-z0-9][a-z0-9._-]*(/[a-z0-9._-]+)?$ ]]; then
  echo "Invalid npm package name: $NAME" >&2
  exit 1
fi

if [[ ! -f "$PLUGIN_DIR/index.js" ]]; then
  echo "index.js not found at $PLUGIN_DIR/index.js" >&2
  exit 1
fi

# ---- 4. Check git status (warn if dirty) ----------------------------------
if command -v git >/dev/null 2>&1; then
  if [[ -d "$SCRIPT_DIR/.git" ]]; then
    pushd "$SCRIPT_DIR" >/dev/null
    if ! git diff --quiet HEAD 2>/dev/null || [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
      echo "WARNING: working tree has uncommitted changes:" >&2
      git status --porcelain 2>/dev/null | sed 's/^/  /'
      if [[ $DRY_RUN -eq 0 ]]; then
        read -p "Continue anyway? [y/N] " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
          echo "Aborted." >&2
          exit 1
        fi
      fi
    fi
    popd >/dev/null
  fi
fi

# ---- 5. npm publish --------------------------------------------------------
ARGS=(publish --access public)
[[ $DRY_RUN -eq 1 ]] && ARGS+=(--dry-run)
[[ -n "$TAG" ]] && ARGS+=(--tag "$TAG")

cd "$PLUGIN_DIR"
echo "Running: npm ${ARGS[*]}"
npm "${ARGS[@]}"
cd "$SCRIPT_DIR"

# ---- 6. Summary -------------------------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
  REGISTRY=$(npm config get registry | tr -d '\n' | tr -d '\r')
  echo ""
  echo -e "\033[32mPublished $NAME@$NEW_VERSION\033[0m"
  echo "View at: $REGISTRY/package/$NAME"
  if [[ -n "$TAG" ]]; then
    echo "Dist-tag: $TAG"
  fi
fi