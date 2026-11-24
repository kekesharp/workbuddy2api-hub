#!/usr/bin/env bash
# ==============================================================================
# WorkBuddy2API 网关 · Linux / macOS 安装脚本
#
# 上游仓库已删除（ardeyouxipianyi/workbuddy2api-hub），本仓库是 v2.0.0
# (d234396) 的完整镜像。网关是纯标准库 Python，不装任何三方依赖。
#
#   用法:
#     ./install.sh                      # 装到 ~/.workbuddy2api，只监听 127.0.0.1:8788
#     ./install.sh --dir /opt/wb2api    # 自定义目录（root 下会自动建 systemd 服务）
#     ./install.sh --lan                # 监听 0.0.0.0，局域网可访问（自动要求 API Key）
#     ./install.sh --port 9000          # 换端口
#     ./install.sh --password 'xxx'     # 指定面板密码（默认随机生成）
#     ./install.sh --no-service         # 只铺文件，不注册开机自启
#     ./install.sh --zip xxx.zip        # 从便携包 ZIP 安装（不用仓库目录）
#
#   卸载: ./uninstall.sh
# ==============================================================================
set -euo pipefail

DIR="${HOME}/.workbuddy2api"
PORT=8788
LAN=0
PASSWORD=""
SERVICE=1
ZIP=""
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

green(){ printf '\033[32m%s\033[0m\n' "$*"; }
blue(){ printf '\033[34m%s\033[0m\n' "$*"; }
red(){ printf '\033[31m%s\033[0m\n' "$*"; }
die(){ red "[错误] $*"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --zip) ZIP="$2"; shift 2 ;;
    --lan) LAN=1; shift ;;
    --no-service) SERVICE=0; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
done

blue "==> 1/6 检查 Python"
PY=""
for c in python3.13 python3.12 python3.11 python3.10 python3.9 python3; do
  if command -v "$c" >/dev/null 2>&1; then
    if "$c" -c 'import sys; sys.exit(0 if sys.version_info>=(3,9) else 1)' 2>/dev/null; then PY="$(command -v "$c")"; break; fi
  fi
done
[ -n "$PY" ] || die "需要 Python 3.9+（apt install python3 / brew install python）"
green "    $PY  $("$PY" -V 2>&1)"

blue "==> 2/6 铺文件到 $DIR"
mkdir -p "$DIR"
if [ -n "$ZIP" ]; then
  [ -f "$ZIP" ] || die "找不到 $ZIP"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  unzip -q "$ZIP" -d "$TMP"
  SRC="$(find "$TMP" -maxdepth 2 -name wb_proxy.py -printf '%h\n' 2>/dev/null | head -1 || true)"
  [ -n "$SRC" ] || SRC="$(find "$TMP" -maxdepth 3 -name wb_proxy.py | head -1 | xargs dirname)"
  [ -n "$SRC" ] || die "ZIP 里找不到 wb_proxy.py"
else
  # 仓库里 installer/ 的上一级就是网关根目录
  SRC="$(cd "$HERE/.." && pwd)"
  [ -f "$SRC/wb_proxy.py" ] || die "在 $SRC 找不到 wb_proxy.py"
fi
# 只搬运行所需的文件，绝不覆盖已有用户数据（accounts/ usage/ catalog 缓存）
for f in wb_*.py dashboard.html console_tail.py LICENSE README.md; do
  [ -e "$SRC/$f" ] && cp -f "$SRC/$f" "$DIR/"
done
[ -d "$SRC/pricing" ] && mkdir -p "$DIR/pricing" && cp -f "$SRC"/pricing/*.json "$DIR/pricing/" 2>/dev/null || true
[ -d "$SRC/ops" ] && mkdir -p "$DIR/ops" && cp -Rf "$SRC"/ops/. "$DIR/ops/" 2>/dev/null || true
mkdir -p "$DIR/accounts" "$DIR/usage"
green "    $(ls "$DIR"/wb_*.py | wc -l | tr -d ' ') 个模块"

blue "==> 3/6 写启动脚本"
HOSTARG="127.0.0.1"
[ "$LAN" -eq 1 ] && HOSTARG="0.0.0.0"
cat > "$DIR/start-wb-proxy.sh" <<EOS
#!/usr/bin/env bash
cd "\$(dirname "\$0")" || exit 1
exec "$PY" wb_proxy.py --host $HOSTARG --port $PORT \${WB_EXTRA_ARGS:-}
EOS
chmod +x "$DIR/start-wb-proxy.sh"

if [ -z "$PASSWORD" ]; then
  PASSWORD="$("$PY" - <<'EOS'
import secrets, string
a = string.ascii_letters + string.digits
print("".join(secrets.choice(a) for _ in range(12)))
EOS
)"
fi

blue "==> 4/6 注册开机自启"
if [ "$SERVICE" -eq 1 ] && [ "$(uname -s)" = "Linux" ] && command -v systemctl >/dev/null 2>&1; then
  UNIT="${HOME}/.config/systemd/user/workbuddy2api.service"
  mkdir -p "$(dirname "$UNIT")"
  cat > "$UNIT" <<EOS
[Unit]
Description=WorkBuddy2API gateway
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$DIR
ExecStart=$DIR/start-wb-proxy.sh
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOS
  systemctl --user daemon-reload
  systemctl --user enable --now workbuddy2api.service
  # 让用户级服务在未登录时也活着（可选，失败不致命）
  loginctl enable-linger "$(id -un)" 2>/dev/null || true
  green "    systemd --user: workbuddy2api.service"
elif [ "$SERVICE" -eq 1 ] && [ "$(uname -s)" = "Darwin" ]; then
  PLIST="${HOME}/Library/LaunchAgents/com.kekesharp.workbuddy2api.plist"
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.kekesharp.workbuddy2api</string>
  <key>ProgramArguments</key><array><string>$DIR/start-wb-proxy.sh</string></array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$DIR/gateway.log</string>
  <key>StandardErrorPath</key><string>$DIR/gateway.err.log</string>
</dict></plist>
EOS
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  green "    launchd: com.kekesharp.workbuddy2api"
else
  green "    跳过（--no-service 或没有 systemd/launchd）"
fi

blue "==> 5/6 起服务并设置面板密码"
if ! curl -fsS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  # </dev/null 必须加：否则后台网关会继承调用者的 stdout 管道，脚本看起来"跑完了不退出"
  ( cd "$DIR" && nohup ./start-wb-proxy.sh >"$DIR/gateway.log" 2>&1 </dev/null & )
fi
for i in $(seq 1 30); do
  curl -fsS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
  sleep 1
done
if curl -fsS --max-time 3 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  ( cd "$DIR" && "$PY" -c "
import sys
sys.path.insert(0,'.')
import wb_settings
wb_settings.set_panel_password('accounts', '''$PASSWORD''')
print('    panel password set')
" 2>/dev/null ) || true
  if [ "$SERVICE" -eq 1 ] && [ "$(uname -s)" = "Linux" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user restart workbuddy2api.service
    sleep 2
  fi
else
  red "    服务没起来，看 $DIR/gateway.log"
fi

blue "==> 6/6 验收"
curl -s --max-time 5 "http://127.0.0.1:$PORT/health" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); print("    health   ok=%s realm=%s accounts=%s" % (d.get("ok"), d.get("realm"), d.get("accounts")))' 2>/dev/null || red "    /health 无响应"
MODELS="$(curl -s --max-time 8 "http://127.0.0.1:$PORT/v1/models" | "$PY" -c 'import json,sys; print(len(json.load(sys.stdin).get("data") or []))' 2>/dev/null || echo 0)"
green "    models   ${MODELS} 个"

cat <<EOS

────────────────────────────────────────────────────────────
 网关地址   http://127.0.0.1:$PORT
 OpenAI API http://127.0.0.1:$PORT/v1
 面板       http://127.0.0.1:$PORT/     面板密码: $PASSWORD
 安装目录   $DIR
 日志       $DIR/gateway.log
────────────────────────────────────────────────────────────
下一步：
 1. 打开面板 → 登录 WorkBuddy / CodeBuddy 账号（accounts=0 时模型能列但对话会失败）
 2. DSH 里配 provider：baseURL http://127.0.0.1:$PORT/v1，apiKey 随便填（本地代理）
 3. 局域网友好模式用 --lan 重装，并对内网开 $PORT 端口
EOS
