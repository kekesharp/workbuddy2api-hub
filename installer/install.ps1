# install.ps1 — WorkBuddy2API 网关 · Windows 安装脚本
#
# 上游仓库已删除（ardeyouxipianyi/workbuddy2api-hub），本仓库是 v2.0.0 (d234396) 的完整镜像。
# 网关是纯标准库 Python，不装任何三方依赖，只要有 python.exe 就能跑。
#
#   .\install.ps1                          # 装到 %LOCALAPPDATA%\workbuddy2api，只听 127.0.0.1:8788
#   .\install.ps1 -Dir C:\tools\wb2api     # 自定义目录
#   .\install.ps1 -Lan                     # 监听 0.0.0.0 + 开防火墙（局域网其他机器可用）
#   .\install.ps1 -Port 9000
#   .\install.ps1 -Password 'xxx'          # 面板密码，默认随机 12 位
#   .\install.ps1 -Zip .\workbuddy2api-2.0.0-portable-win-x64.zip   # 从便携包装（自带 python）
#   .\install.ps1 -NoTask                  # 不注册开机自启

param(
  [string]$Dir = (Join-Path $env:LOCALAPPDATA "workbuddy2api"),
  [int]$Port = 8788,
  [switch]$Lan,
  [string]$Password = "",
  [string]$Zip = "",
  [switch]$NoTask
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Say($m) { Write-Host "==> $m" }
function Fail($m) { Write-Host "[错误] $m" -ForegroundColor Red; exit 1 }
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── 1. 找 python ─────────────────────────────────────────────────────────────
Say "1/6 检查 Python"
$Py = $null
if ($Zip) {
  if (-not (Test-Path $Zip)) { Fail "找不到 $Zip" }
  Say "    解压便携包"
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  Expand-Archive -Path $Zip -DestinationPath $Dir -Force
  # 便携包内层是 wb-proxy\ 目录
  $inner = Join-Path $Dir "wb-proxy"
  if (Test-Path (Join-Path $inner "wb_proxy.py")) {
    Get-ChildItem $inner -Force | Move-Item -Destination $Dir -Force
    Remove-Item $inner -Recurse -Force -ErrorAction SilentlyContinue
  }
  $emb = Join-Path $Dir "python\python.exe"
  if (Test-Path $emb) { $Py = $emb; Say "    用包内运行时 python 3.12" }
} else {
  $src = Split-Path -Parent $Here
  if (-not (Test-Path (Join-Path $src "wb_proxy.py"))) { Fail "在 $src 找不到 wb_proxy.py（应在仓库根目录的 installer\ 下运行）" }
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  foreach ($f in @(Get-ChildItem $src -Filter "wb_*.py") + @(Get-ChildItem $src -Include "dashboard.html","console_tail.py","LICENSE","README.md" -File)) {
    if ($f -and (Test-Path $f.FullName)) { Copy-Item $f.FullName $Dir -Force }
  }
  foreach ($d in @("pricing","ops")) {
    $p = Join-Path $src $d
    if (Test-Path $p) { Copy-Item $p (Join-Path $Dir $d) -Recurse -Force }
  }
}
if (-not $Py) {
  foreach ($c in @("python.exe","python3.exe")) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) {
      & $cmd.Source -c "import sys; sys.exit(0 if sys.version_info>=(3,9) else 1)" 2>$null
      if ($LASTEXITCODE -eq 0) { $Py = $cmd.Source; break }
    }
  }
}
if (-not $Py) {
  $cands = @("C:\Program Files\Python313\python.exe","C:\Program Files\Python312\python.exe","C:\Program Files\Python311\python.exe","C:\Program Files\Python310\python.exe",(Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"))
  foreach ($c in $cands) { if (Test-Path $c) { $Py = $c; break } }
}
if (-not $Py) { Fail "找不到 Python 3.9+。装一个（winget install Python.Python.3.12）或用 -Zip 便携包" }
Say "    $Py  $(& $Py -V 2>&1)"

New-Item -ItemType Directory -Force -Path (Join-Path $Dir "accounts"),(Join-Path $Dir "usage") | Out-Null
$n = (Get-ChildItem $Dir -Filter "wb_*.py").Count
Say "    $n 个模块 → $Dir"

# ── 2. 启动包装脚本（计划任务的 action 必须是 .cmd，别塞引号进 schtasks）────
Say "2/6 写启动脚本"
$hostArg = if ($Lan) { "0.0.0.0" } else { "127.0.0.1" }
$startCmd = Join-Path $Dir "start-wb-proxy.cmd"
$body = @"
@echo off
cd /d "%~dp0"
"$Py" wb_proxy.py --host $hostArg --port $Port %*
"@
[System.IO.File]::WriteAllText($startCmd, ($body -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)

if (-not $Password) {
  $chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789".ToCharArray()
  $Password = -join (1..12 | ForEach-Object { $chars | Get-Random })
}

# ── 3. 开机自启 ─────────────────────────────────────────────────────────────
Say "3/6 注册开机自启"
if (-not $NoTask) {
  $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$startCmd`"" -WorkingDirectory $Dir
  $trg = New-ScheduledTaskTrigger -AtLogOn
  $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
  $prn = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$env:USERNAME" -LogonType Interactive -RunLevel Limited
  Unregister-ScheduledTask -TaskName "WorkBuddy2API" -Confirm:$false -ErrorAction SilentlyContinue
  Register-ScheduledTask -TaskName "WorkBuddy2API" -Action $act -Trigger $trg -Settings $set -Principal $prn `
    -Description "WorkBuddy2API gateway" | Out-Null
  Say "    计划任务 WorkBuddy2API（登录时启动）"
}

# ── 4. 局域网放行 ───────────────────────────────────────────────────────────
if ($Lan) {
  Say "4/6 放行防火墙 $Port"
  Remove-NetFirewallRule -DisplayName "WorkBuddy2API $Port" -ErrorAction SilentlyContinue
  New-NetFirewallRule -DisplayName "WorkBuddy2API $Port" -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort $Port -Profile Private | Out-Null
} else { Say "4/6 跳过防火墙（只听 127.0.0.1）" }

# ── 5. 起服务 + 设面板密码 ──────────────────────────────────────────────────
Say "5/6 启动并设置面板密码"
try { Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 2 | Out-Null }
catch {
  if (-not $NoTask) { Start-ScheduledTask -TaskName "WorkBuddy2API" }
  else { Start-Process -FilePath $startCmd -WorkingDirectory $Dir -WindowStyle Hidden }
}
$ok = $false
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Seconds 1
  try { $h = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3; $ok = $true; break } catch { }
}
if ($ok) {
  Push-Location $Dir
  $env:PYTHONPATH = $Dir
  & $Py -c "import sys; sys.path.insert(0,'.'); import wb_settings; wb_settings.set_panel_password('accounts','''$Password'''); print('    panel password set')"
  Pop-Location
} else {
  Write-Host "    服务没起来，看 $Dir\gateway.log" -ForegroundColor Red
}

# ── 6. 验收 ─────────────────────────────────────────────────────────────────
Say "6/6 验收"
$models = 0
try { $models = (Invoke-RestMethod "http://127.0.0.1:$Port/v1/models" -TimeoutSec 8).data.Count } catch { }
Write-Host ""
Write-Host "────────────────────────────────────────────────────────────"
Write-Host " 网关地址   http://127.0.0.1:$Port"
Write-Host " OpenAI API http://127.0.0.1:$Port/v1"
Write-Host " 面板       http://127.0.0.1:$Port/    密码: $Password"
Write-Host " 安装目录   $Dir"
Write-Host " 日志       $Dir\gateway.log"
Write-Host " health     ok=$($h.ok) realm=$($h.realm) accounts=$($h.accounts)  models=$models"
Write-Host "────────────────────────────────────────────────────────────"
Write-Host @"
下一步：
 1. 打开面板 → 登录 WorkBuddy / CodeBuddy 账号（accounts=0 时模型能列但对话会失败）
 2. DSH / 任意 OpenAI 客户端：baseURL http://127.0.0.1:$Port/v1
 3. 卸载：.\uninstall.ps1
"@
