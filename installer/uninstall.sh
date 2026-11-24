#!/usr/bin/env bash
# WorkBuddy2API 卸载：停服务、删自启、删程序文件，保留 accounts/ 与 usage/ 除非加 --purge
set -uo pipefail
DIR="${1:-$HOME/.workbuddy2api}"
PURGE=0
[ "${2:-}" = "--purge" ] && PURGE=1

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now workbuddy2api.service 2>/dev/null
  rm -f "$HOME/.config/systemd/user/workbuddy2api.service"
  systemctl --user daemon-reload 2>/dev/null
fi
PLIST="$HOME/Library/LaunchAgents/com.kekesharp.workbuddy2api.plist"
if [ -f "$PLIST" ]; then launchctl unload "$PLIST" 2>/dev/null; rm -f "$PLIST"; fi
pkill -f "wb_proxy.py" 2>/dev/null

if [ "$PURGE" -eq 1 ]; then
  rm -rf "$DIR"; echo "已删除 $DIR（含账号数据）"
else
  find "$DIR" -maxdepth 1 -name 'wb_*.py' -delete 2>/dev/null
  rm -f "$DIR/dashboard.html" "$DIR/console_tail.py" "$DIR/start-wb-proxy.sh"
  echo "已删程序文件，保留 $DIR/accounts 与 $DIR/usage（要全删：./uninstall.sh $DIR --purge）"
fi
