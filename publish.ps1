# publish.ps1 — publish the trusted plugin to npm registry (Windows / PowerShell)
#
# 用法：
#   .\publish.ps1                                  # 用 package.json 里的当前 version
#   .\publish.ps1 -Bump patch                       # patch bump (1.0.0 → 1.0.1)
#   .\publish.ps1 -Bump minor                       # minor bump (1.0.0 → 1.1.0)
#   .\publish.ps1 -Bump major                       # major bump (1.0.0 → 2.0.0)
#   .\publish.ps1 -DryRun                           # 不真发布，只检查
#   .\publish.ps1 -Tag beta                         # 打 tag beta + @beta dist-tag
#
# 前提：先 `npm login` 或 `npm adduser` 登录 npmjs.org

[CmdletBinding()]
param(
  [ValidateSet('patch', 'minor', 'major', 'none')]
  [string]$Bump = 'none',
  [switch]$DryRun,
  [string]$Tag = ''
)

$ErrorActionPreference = 'Stop'

$PluginDir = Join-Path $PSScriptRoot 'trusted-plugin'
$PkgJson = Join-Path $PluginDir 'package.json'

if (-not (Test-Path $PkgJson)) {
  throw "package.json not found at $PkgJson"
}

# ---- 1. Read current version ----------------------------------------------
$pkg = Get-Content $PkgJson -Raw | ConvertFrom-Json
$name = $pkg.name
$oldVersion = $pkg.version
Write-Host "Package: $name"
Write-Host "Current version: $oldVersion"

# ---- 2. Bump version if requested ------------------------------------------
function Bump-Version([string]$v, [string]$kind) {
  if ($kind -eq 'none') { return $v }
  $parts = $v.Split('.') | ForEach-Object { [int]$_ }
  switch ($kind) {
    'major' { $parts[0]++; $parts[1] = 0; $parts[2] = 0 }
    'minor' { $parts[1]++; $parts[2] = 0 }
    'patch' { $parts[2]++ }
  }
  return ($parts -join '.')
}

$newVersion = Bump-Version $oldVersion $Bump
if ($newVersion -ne $oldVersion) {
  $pkg.version = $newVersion
  $pkg | ConvertTo-Json -Depth 10 | Set-Content -Path $PkgJson -Encoding utf8NoBOM
  Write-Host "Bumped to: $newVersion"
} else {
  Write-Host "No version bump"
}

# ---- 3. Sanity checks ------------------------------------------------------
if ($name -notmatch '^@?[a-z0-9][a-z0-9._-]*(/[a-z0-9._-]+)?$') {
  throw "Invalid npm package name: $name"
}

$indexJs = Join-Path $PluginDir 'index.js'
if (-not (Test-Path $indexJs)) {
  throw "index.js not found at $indexJs"
}

# ---- 4. Check git status (warn if dirty) ----------------------------------
Push-Location $PSScriptRoot
try {
  $gitStatus = & git status --porcelain 2>$null
  if ($gitStatus) {
    Write-Host "WARNING: working tree has uncommitted changes:" -ForegroundColor Yellow
    $gitStatus | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    if (-not $DryRun) {
      $confirm = Read-Host "Continue anyway? [y/N]"
      if ($confirm -ne 'y' -and $confirm -ne 'Y') { throw "Aborted by user." }
    }
  }
} catch {
  Write-Host "git not available — skipping status check" -ForegroundColor Yellow
}
Pop-Location

# ---- 5. npm publish --------------------------------------------------------
Push-Location $PluginDir
try {
  $args = @('publish', '--access', 'public')
  if ($DryRun) { $args += '--dry-run' }
  if ($Tag) { $args += '--tag', $Tag }
  Write-Host "Running: npm $($args -join ' ')"
  & npm @args
  if ($LASTEXITCODE -ne 0) {
    throw "npm publish failed with exit code $LASTEXITCODE"
  }
}
finally {
  Pop-Location
}

# ---- 6. Summary -------------------------------------------------------------
if (-not $DryRun) {
  $registry = (& npm config get registry) -replace "`n", "" -replace "`r", ""
  Write-Host ""
  Write-Host "Published $name@$newVersion" -ForegroundColor Green
  Write-Host "View at: $registry/package/$name"
  if ($Tag) {
    Write-Host "Dist-tag: $Tag"
  }
}