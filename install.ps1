# install.ps1 — MiniMax 用量插件一键部署脚本 (Windows / PowerShell)
#
# macOS / Linux 请用 install.sh
#
# DSH 官方 plugin 结构（已验证 ~/.dsh/profiles/web/node_modules/minimax-usage/index.js）：
#
#   ~/.dsh/profiles/web/
#   ├── minimax-usage/                       ← 包源码（本脚本部署到这里）
#   │   └── index.js
#   ├── node_modules/minimax-usage/           ← pnpm workspace 符号链接 → ../minimax-usage/
#   ├── package.json                          ← 依赖 "minimax-usage": "workspace:*"
#   ├── pnpm-workspace.yaml                   ← packages: [., minimax-usage]
#   └── cordis.patch.yml                      ← - insert: [{ id: minimax-usage, name: minimax-usage }]
#
# 用法：
#   .\install.ps1                                 # 本地源码模式
#   .\install.ps1 -Source npm -NpmName @you/pkg    # npm 模式
#   .\install.ps1 -ApiKey 'sk-cp-...'             # 直接传 key
#   .\install.ps1 -SkipKey                        # 只部署，不写 key
#   .\install.ps1 -DshHome 'D:\custom\.dsh'       # 自定义 DSH home
#
# 注意：trusted plugin 修改后必须重启 DSH 主进程才会重新加载。

[CmdletBinding()]
param(
  [ValidateSet('local', 'npm')]
  [string]$Source = 'local',
  [string]$NpmName = '@dsh-extras/minimax-usage',
  [string]$ApiKey = "",
  [string]$DshHome = "",
  [switch]$SkipKey
)

$ErrorActionPreference = 'Stop'

# ---- 0. Resolve DSH home ---------------------------------------------------
if (-not $DshHome) {
  $DshHome = $env:DSH_HOME
  if (-not $DshHome) {
    $DshHome = Join-Path $env:USERPROFILE '.dsh'
  }
}
$ProfileDir = Join-Path $DshHome 'profiles\web'
Write-Host "DSH home: $DshHome"
Write-Host "Profile dir: $ProfileDir"
Write-Host "Source: $Source"

if (-not (Test-Path $ProfileDir)) {
  throw "DSH web profile not found at $ProfileDir. Install DSH first."
}

# ---- 1. Deploy trusted plugin ---------------------------------------------
$PackageDir = Join-Path $ProfileDir 'minimax-usage'
$NodeModulesLink = Join-Path $ProfileDir 'node_modules\minimax-usage'

switch ($Source) {
  'local' {
    $PluginSrc = Join-Path $PSScriptRoot 'trusted-plugin\index.js'
    if (-not (Test-Path $PluginSrc)) {
      throw "Trusted plugin source not found: $PluginSrc"
    }
    if (-not (Test-Path $PackageDir)) {
      New-Item -ItemType Directory -Force -Path $PackageDir | Out-Null
    }
    Copy-Item -Path $PluginSrc -Destination (Join-Path $PackageDir 'index.js') -Force
    Write-Host "Deployed local source -> $PackageDir\index.js"
  }
  'npm' {
    Write-Host "Will install $NpmName from npm in the DSH profile..."
    $ProfilePkg = Join-Path $ProfileDir 'package.json'
    if (-not (Test-Path $ProfilePkg)) {
      throw "$ProfilePkg not found"
    }
    $pkg = Get-Content $ProfilePkg -Raw | ConvertFrom-Json
    $pkg.dependencies | Add-Member -NotePropertyName $NpmName.Split('/')[-1] -NotePropertyValue $NpmName -Force
    $pkg | ConvertTo-Json -Depth 10 | Set-Content -Path $ProfilePkg -Encoding utf8NoBOM
    Write-Host "Added $NpmName to $ProfilePkg dependencies"
  }
}

# Verify or create the node_modules symlink (only for local mode; npm mode handles its own)
if ($Source -eq 'local') {
  if (Test-Path $NodeModulesLink) {
    $existing = Get-Item $NodeModulesLink -Force
    Write-Host "Workspace link exists: $NodeModulesLink -> $($existing.Target)"
  } else {
    $nodeModulesDir = Join-Path $ProfileDir 'node_modules'
    if (-not (Test-Path $nodeModulesDir)) { New-Item -ItemType Directory -Force -Path $nodeModulesDir | Out-Null }
    cmd /c mklink /J "$NodeModulesLink" "$PackageDir" | Out-Null
    Write-Host "Created junction: $NodeModulesLink -> $PackageDir"
  }
}

# ---- 2. Run npm/pnpm install (npm mode: install package; local mode: install workspace) ----
$npm = Get-Command pnpm -ErrorAction SilentlyContinue
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue

if ($Source -eq 'npm') {
  if ($npmCmd) {
    Write-Host "Running npm install in $ProfileDir ..."
    Push-Location $ProfileDir
    try { & npm install 2>&1 | Out-Host } catch { Write-Host "npm install failed: $_" -ForegroundColor Yellow }
    Pop-Location
  } else {
    Write-Host "npm not on PATH — install it and run 'npm install' in $ProfileDir manually" -ForegroundColor Yellow
  }
} else {
  if ($npm) {
    Write-Host "Running pnpm install in $ProfileDir ..."
    Push-Location $ProfileDir
    try { & pnpm install 2>&1 | Out-Host } catch { Write-Host "pnpm install failed: $_" -ForegroundColor Yellow }
    Pop-Location
  } else {
    Write-Host "pnpm not on PATH — skipping install. If DSH fails to load, run 'pnpm install' in $ProfileDir" -ForegroundColor Yellow
  }
}

# ---- 3. Verify / patch profile package.json -------------------------------
$ProfilePkg = Join-Path $ProfileDir 'package.json'
if (Test-Path $ProfilePkg) {
  if ($Source -eq 'local') {
    $pkg = Get-Content $ProfilePkg -Raw | ConvertFrom-Json
    if (-not $pkg.dependencies.'minimax-usage') {
      $pkg.dependencies | Add-Member -NotePropertyName 'minimax-usage' -NotePropertyValue 'workspace:*' -Force
      $pkg | ConvertTo-Json -Depth 10 | Set-Content -Path $ProfilePkg -Encoding utf8NoBOM
      Write-Host "Added workspace:* dependency to $ProfilePkg"
    } else {
      Write-Host "package.json already has minimax-usage dependency"
    }
  } else {
    Write-Host "package.json has $NpmName (added in step 1)"
  }
}

# ---- 4. Verify / patch pnpm-workspace.yaml --------------------------------
if ($Source -eq 'local') {
  $WorkspaceYaml = Join-Path $ProfileDir 'pnpm-workspace.yaml'
  if (Test-Path $WorkspaceYaml) {
    $content = Get-Content $WorkspaceYaml -Raw
    if ($content -notmatch 'minimax-usage') {
      $content = $content -replace "(?m)^packages:\s*$", "packages:`n  - .`n  - minimax-usage"
      if ($content -notmatch 'minimax-usage') {
        $content += "`n  - minimax-usage`n"
      }
      Set-Content -Path $WorkspaceYaml -Value $content -Encoding utf8NoBOM
      Write-Host "Added minimax-usage to $WorkspaceYaml"
    } else {
      Write-Host "pnpm-workspace.yaml already lists minimax-usage"
    }
  }
}

# ---- 5. Verify / patch cordis.patch.yml ------------------------------------
$PatchYaml = Join-Path $ProfileDir 'cordis.patch.yml'
if (Test-Path $PatchYaml) {
  $content = Get-Content $PatchYaml -Raw
  if ($content -notmatch '^\s*-\s*id:\s*minimax-usage' -and $content -notmatch 'id:\s*minimax-usage') {
    $append = "`n# Trusted MiniMax usage plugin: registers the minimaxUsage service`n- insert:`n    - id: minimax-usage`n      name: minimax-usage`n"
    Set-Content -Path $PatchYaml -Value ($content + $append) -Encoding utf8NoBOM
    Write-Host "Added insert row to $PatchYaml"
  } else {
    Write-Host "cordis.patch.yml already has minimax-usage insert"
  }
}

# ---- 6. Configure API key -------------------------------------------------
$resolvedKey = $null
if (-not $SkipKey) {
  if ($ApiKey) {
    $resolvedKey = $ApiKey.Trim()
  } elseif ($env:MINIMAX_API_KEY) {
    $resolvedKey = $env:MINIMAX_API_KEY.Trim()
    Write-Host "Using existing MINIMAX_API_KEY environment variable."
  }

  if (-not $resolvedKey) {
    Write-Host ""
    Write-Host "MINIMAX_API_KEY is not set."
    Write-Host "Get your Token Plan key from https://www.minimaxi.com/ (NOT the metered-billing key)."
    Write-Host ""
    $secure = Read-Host "Paste your MINIMAX_API_KEY (input hidden if supported)" -AsSecureString
    if ($secure) {
      $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
      $resolvedKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    } else {
      $resolvedKey = Read-Host "Paste your MINIMAX_API_KEY"
    }
  }

  if ($resolvedKey) {
    $credFile = Join-Path $DshHome '.credentials.yaml'
    $keyLine = "MINIMAX_API_KEY: '" + $resolvedKey.Replace("'", "''") + "'"
    if (Test-Path $credFile) {
      $existing = Get-Content $credFile -Raw -ErrorAction SilentlyContinue
      if ($existing -match '(?m)^\s*MINIMAX_API_KEY\s*:') {
        $existing = [regex]::Replace($existing, '(?m)^\s*MINIMAX_API_KEY\s*:.*$', $keyLine)
      } else {
        if (-not $existing.EndsWith("`n")) { $existing += "`n" }
        $existing += $keyLine + "`n"
      }
      Set-Content -Path $credFile -Value $existing -Encoding utf8NoBOM
    } else {
      Set-Content -Path $credFile -Value ($keyLine + "`n") -Encoding utf8NoBOM
    }
    Write-Host "Wrote MINIMAX_API_KEY to $credFile"
  }
}

# ---- 7. Summary and next-step instructions --------------------------------
if ($resolvedKey) {
  Write-Host ""
  Write-Host "API key configured. Sanity check:" -ForegroundColor Green
  Write-Host "  Length: $($resolvedKey.Length)"
  Write-Host "  Prefix: $($resolvedKey.Substring(0, [Math]::Min(7, $resolvedKey.Length)))..."
} else {
  Write-Host ""
  Write-Host "WARNING: no API key was set. Plugin will return 'missing_key' until you" -ForegroundColor Yellow
  Write-Host "         add MINIMAX_API_KEY to env or to $DshHome\.credentials.yaml"
}

Write-Host ""
Write-Host "=== NEXT STEPS ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. RESTART DSH (the trusted plugin only loads at main-process startup):"
Write-Host "   - Close the DSH desktop window completely"
Write-Host "   - Reopen DSH"
Write-Host ""
Write-Host "2. In a new DSH session, send this message to the agent:"
Write-Host ""
Write-Host '   请加载并启用 MiniMax 用量插件，依次执行：'
Write-Host '   1) cordis_define 用 D:\Code\tools-plugin\minimax-usage-plugin\cordis_define_payload.json'
Write-Host '      的完整 JSON 作为参数（plugin / name / purpose / code 四个字段都在里面）'
Write-Host '   2) 拿到返回的 pluginId 和 packageId 后，cordis_run 调 mode="run"'
Write-Host '   3) 如果提示 awaiting-approval，请点浏览器顶部的「同意」授权该客户端包'
Write-Host ""
Write-Host "   The plugin will mount a "用量" section in Settings."
Write-Host ""
Write-Host "3. Open Settings page → "用量" section to see the cards."
Write-Host ""