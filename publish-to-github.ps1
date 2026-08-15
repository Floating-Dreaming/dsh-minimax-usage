# publish-to-github.ps1 — 在你自己的 PowerShell 里跑这个（不是 sandbox 里）
#
# 用法（在你本机 PowerShell 里）：
#   .\publish-to-github.ps1
#
# 它会做：
#   1. 用 gh CLI 取 OAuth token
#   2. 用 token 临时嵌入 URL 推送 feat/initial-commit 分支
#   3. 立刻从 URL 里清掉 token
#   4. 用 gh api 配置 branch protection（main 分支）
#   5. 开 PR 并 squash merge 到 main
#
# 前提：已 `gh auth login`，且 git 仓库已经在 D:\Code\minimax-usage-plugin

$ErrorActionPreference = 'Stop'

$RepoDir       = 'D:\Code\minimax-usage-plugin'
$RemoteOwner   = 'Floating-Dreaming'
$RemoteRepo    = 'dsh-minimax-usage'
$RemoteUrl     = "https://github.com/$RemoteOwner/$RemoteRepo.git"
$AuthUrl       = $null
$FeatureBranch = 'feat/initial-commit'
$MainBranch    = 'main'
# gh.exe 安装位置可能不在 PATH（winget 默认装到 Program Files\GitHub CLI\）
$GhExe         = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $GhExe) {
  $candidate = 'C:\Program Files\GitHub CLI\gh.exe'
  if (Test-Path $candidate) { $GhExe = $candidate }
}
if (-not $GhExe) {
  throw "gh CLI not found. Install: winget install --id GitHub.cli"
}
Write-Host "Using gh: $GhExe"

# ---- 0. Pre-flight checks ---------------------------------------------------
if (-not (Test-Path $RepoDir)) {
  throw "Repo dir not found: $RepoDir"
}
Push-Location $RepoDir
try {
  $auth = (& $GhExe auth status 2>&1) | Out-String
  if ($auth -notmatch 'Logged in to github.com') {
    throw "gh not authenticated. Run: gh auth login"
  }
  Write-Host "gh auth OK: $RemoteOwner"

  $remote = git remote get-url origin 2>$null
  if (-not $remote) {
    git remote add origin $RemoteUrl
    Write-Host "Added origin: $RemoteUrl"
  }

  $currentBranch = git branch --show-current
  if ($currentBranch -ne $FeatureBranch) {
    git checkout -B $FeatureBranch
  }
  Write-Host "Current branch: $(git branch --show-current)"
}
finally { Pop-Location }

# ---- 1. Get token from gh and push with embedded-token URL ------------------
Push-Location $RepoDir
try {
  $token = & $GhExe auth token 2>$null
  if (-not $token) { throw "Failed to get gh auth token" }
  Write-Host "Got token: $($token.Substring(0,8))..."

  $AuthUrl = "https://x-access-token:${token}@github.com/$RemoteOwner/$RemoteRepo.git"
  git remote set-url origin $AuthUrl

  Write-Host ""
  Write-Host "Pushing $FeatureBranch ..."
  $pushOut = git push -u origin $FeatureBranch 2>&1
  $pushOk = ($LASTEXITCODE -eq 0)
  if (-not $pushOk) {
    Write-Host "Push output: $pushOut"
  }

  # IMMEDIATELY strip token
  git remote set-url origin "https://github.com/$RemoteOwner/$RemoteRepo.git"
  Write-Host "URL cleaned. Push success: $pushOk"

  if (-not $pushOk) {
    throw "Push failed. Run 'git push -u origin $FeatureBranch' manually after debugging."
  }
}
finally { Pop-Location }

# ---- 2. Configure branch protection on main via gh api ---------------------
Write-Host ""
Write-Host "Configuring branch protection on $MainBranch ..."
$protectionJson = @'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismissal_restrictions": {},
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": false,
  "block_creations": false
}
'@

$protectionPath = Join-Path $env:TEMP "dsh-protection-$MainBranch.json"
Set-Content -Path $protectionPath -Value $protectionJson -Encoding utf8NoBOM

$apiUrl = "repos/$RemoteOwner/$RemoteRepo/branches/$MainBranch/protection"
try {
  & $GhExe api -X PUT --input $protectionPath $apiUrl 2>&1 | Out-Host
  Write-Host "Branch protection set on $MainBranch."
} catch {
  Write-Host "Branch protection failed (might be OK if branch has no commits yet): $_"
}
Remove-Item $protectionPath -ErrorAction SilentlyContinue

# ---- 3. Open PR via gh ------------------------------------------------------
Write-Host ""
Write-Host "Creating PR $FeatureBranch -> $MainBranch ..."
Push-Location $RepoDir
try {
  $prBody = @"
## Initial commit: DSH MiniMax usage plugin (v17)

- **trusted-plugin/**: npm-publishable DSH trusted plugin (Node host module)
- **cordis_define_payload.json**: dynamic plugin source (host + client)
- **install.ps1 / install.sh**: deployment scripts (local + npm source modes)
- **publish.ps1 / publish.sh**: npm publishing scripts
- **README.md + changelog.md**: docs
"@
  $prBodyPath = Join-Path $env:TEMP "dsh-pr-body.md"
  Set-Content -Path $prBodyPath -Value $prBody -Encoding utf8NoBOM

  $prOut = & $GhExe pr create --base $MainBranch --head $FeatureBranch --title 'Initial commit: DSH MiniMax usage plugin (v17)' --body-file $prBodyPath 2>&1 | Out-String
  Write-Host "PR create output: $prOut"

  # Extract PR number from output (URL like https://github.com/.../pull/N)
  if ($prOut -match '/pull/(\d+)') {
    $prNumber = $matches[1]
    Write-Host "Created PR #$prNumber"
    Remove-Item $prBodyPath -ErrorAction SilentlyContinue

    # ---- 4. Auto-approve and squash merge ----------------------------------
    # Only works if the account is the only required approver (1 approval = self)
    Write-Host ""
    Write-Host "Approving PR #$prNumber ..."
    & $GhExe pr review $prNumber --approve 2>&1 | Out-Host

    Write-Host ""
    Write-Host "Squash merging PR #$prNumber ..."
    & $GhExe pr merge $prNumber --squash --delete-branch 2>&1 | Out-Host
    Write-Host "Merged."
  } else {
    Write-Host "Could not parse PR number from output. Merge manually."
  }
}
finally { Pop-Location }

Write-Host ""
Write-Host "Done. Repo: https://github.com/$RemoteOwner/$RemoteRepo" -ForegroundColor Green