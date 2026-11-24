# WorkBuddy2API 卸载：停计划任务、删自启与程序文件，保留 accounts\ 与 usage\ 除非 -Purge
param([string]$Dir = (Join-Path $env:LOCALAPPDATA "workbuddy2api"), [switch]$Purge)
$ErrorActionPreference = "Continue"
Unregister-ScheduledTask -TaskName "WorkBuddy2API" -Confirm:$false -ErrorAction SilentlyContinue
Get-Process python,pythonw -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Dir*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like "*wb_proxy.py*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
if ($Purge) { Remove-Item $Dir -Recurse -Force; Write-Host "已删除 $Dir（含账号数据）" }
else {
  Get-ChildItem $Dir -Filter "wb_*.py" -ErrorAction SilentlyContinue | Remove-Item -Force
  Remove-Item (Join-Path $Dir "dashboard.html"),(Join-Path $Dir "start-wb-proxy.cmd") -Force -ErrorAction SilentlyContinue
  Write-Host "已删程序文件，保留 $Dir\accounts 与 $Dir\usage（要全删：.\uninstall.ps1 -Purge）"
}
