# 安装指南（WorkBuddy2API 网关）

本仓库是 **`ardeyouxipianyi/workbuddy2api-hub` v2.0.0（commit `d234396`）的完整镜像**。
上游仓库已删除，官方 release 资产再也下不到，所以这里自带一套安装脚本和一个可复现的便携包构建器。

网关本身是**纯 Python 标准库**实现（`wb_*.py`，零三方依赖），只要 Python 3.9+ 或包内自带的
`python/` 运行时就能跑。

---

## 一、先选部署方式

| 方式 | 适合 | 需要什么 | 端口 |
|---|---|---|---|
| **Windows 便携包**（推荐给桌面机） | 只想双击用，不想装 Python | 无（自带 python 3.12） | 8788 |
| **Linux/macOS 脚本安装** | 想开机自启、当服务跑 | Python 3.9+ | 8788 |
| **Docker**（`quick-deploy.sh`） | NAS / 服务器 / 群晖威联通 | Docker | 8788 |

三种方式装的是同一套代码，账号数据目录结构一样（`accounts/`、`usage/`）。

---

## 二、Windows

### 2.1 最省事：便携包

```powershell
# 构建（在 macOS/Linux 上也能跑，产物是 Windows 包）
python3 installer/build-portable-win.py
# → dist/workbuddy2api-2.0.0-portable-win-x64.zip
```

把 zip 拷到 Windows，解压得到 `wb-proxy\`，里面：

- `start-wb-proxy.bat` —— 双击启动（静默模式：无控制台窗口，另开一个日志查看窗）
- `start-wb-proxy-visible.bat` —— 带控制台的启动，排错用
- `python\` —— 自带的 CPython 3.12.10（embeddable），无需系统装 Python

启动后浏览器打开 <http://127.0.0.1:8788/>，默认面板密码 **`admin`**。

### 2.2 装成开机自启：`installer\install.ps1`

```powershell
# 把整个仓库（或解压后的便携包）拷到 Windows，在 installer\ 目录里：
.\install.ps1                          # 装到 %LOCALAPPDATA%\workbuddy2api
.\install.ps1 -Zip ..\dist\workbuddy2api-2.0.0-portable-win-x64.zip
.\install.ps1 -Lan                     # 监听 0.0.0.0 + 自动加防火墙规则
.\install.ps1 -Port 9000 -Password 'my-pass'
```

它做的事：找 Python（包内 `python\python.exe` 优先）→ 铺文件 → 写 `start-wb-proxy.cmd`
→ 注册计划任务 `WorkBuddy2API`（登录时启动，不弹窗）→ 起服务 → 把面板密码设成随机 12 位并打印
→ 打 `/health` 和 `/v1/models` 验收。

> 计划任务用 `-LogonType Interactive`：用户的桌面会话里跑，SSH 断开不会把它带走。
> 若走 SSH 远程装，注意 `Start-Process` 起的进程会随会话结束被杀，别用它起服务。

### 2.3 卸载

```powershell
.\uninstall.ps1            # 删程序文件，保留 accounts\ 与 usage\
.\uninstall.ps1 -Purge     # 连账号数据一起删
```

---

## 三、Linux / macOS

```bash
chmod +x installer/install.sh
./installer/install.sh                       # ~/.workbuddy2api，只听 127.0.0.1:8788
./installer/install.sh --dir /opt/wb2api     # 自定义目录
./installer/install.sh --lan                 # 0.0.0.0，局域网可访问
./installer/install.sh --zip dist/workbuddy2api-2.0.0-portable-win-x64.zip   # 从包里取源码
./installer/install.sh --no-service          # 只铺文件，不注册自启
```

- Linux：注册 **systemd 用户服务** `workbuddy2api.service`，并 `loginctl enable-linger` 让未登录时也活着
- macOS：注册 **launchd** `~/Library/LaunchAgents/com.kekesharp.workbuddy2api.plist`
- 面板密码：脚本随机生成 12 位并写进 `accounts/settings.json`（不再用默认 `admin`）

卸载：

```bash
./installer/uninstall.sh                 # 保留数据
./installer/uninstall.sh "" --purge      # 连数据一起删（第二个参数位置传 --purge）
```

---

## 四、绑定模式与安全

`--lan`（或 `wb_proxy.py --lan`）会：

- 监听 `0.0.0.0`，**并且强制要求 API Key**（`/v1/*` 需要 bearer token），这是上游的设计
- 面板仍然要密码

只在本机用（默认）时监听 `127.0.0.1`，**不要**把 8788 直接暴露到公网。需要远程访问就套
Nginx/Caddy 反代或 Cloudflare Tunnel。

---

## 五、接进 DSH / 任意 OpenAI 客户端

网关对外就是 OpenAI 兼容接口：`http://127.0.0.1:8788/v1`。

`~/.dsh/profiles/<profile>/cordis.patch.yml` 里的 provider 片段：

```yaml
- id: llm-pi-ai
  config:
    providers:
      workbuddy:
        baseURL: http://127.0.0.1:8788/v1
        apiKeyEnv: WORKBUDDY_API_KEY
        models:
          - deepseek-v4.1-flash
          - hy4-preview-f
          - hy3
```

`~/.dsh/.credentials.yaml` 里给 key（本地代理不校验时随便填）：

```yaml
version: 1

refs:
  WORKBUDDY_API_KEY: local-proxy
```

---

## 六、账号从哪来

`accounts/` 里放的是真实的 WorkBuddy / CodeBuddy 凭据。两种来源：

1. **面板里扫码/登录**（推荐）：打开 <http://127.0.0.1:8788/> → 添加账号
2. **从桌面 App 导入**：`python3 wb_proxy.py --import-desktop`

`accounts=0` 时 `/v1/models` 仍然能列模型（内置表），但**对话会失败**。

---

## 七、升级

程序文件（`wb_*.py` / `dashboard.html` / `pricing/`）可以整体覆盖；
**`accounts/` 与 `usage/` 永不替换**——这是上游 `release/portable.txt` 定义的受保护路径，本仓库的
`installer/*` 也遵守同一条规则（复制时只搬 `wb_*.py` 等受管文件）。

---

## 八、故障排查

| 现象 | 原因 / 处理 |
|---|---|
| `No usable Python found` | 用便携包（自带 `python\`），或装 Python 3.9+ 并勾选 Add to PATH |
| 双击 bat 一闪而过 | 换 `start-wb-proxy-visible.bat` 看报错；多半是端口被占 |
| `/health` 200 但对话 400/401 | `accounts=0`，先去面板登录账号 |
| `11-128` 相关报错 | 见 `docs/TROUBLESHOOTING-11-128.md` |
| 局域网连不上 | 用 `--lan` 起，并放行 8788（Windows 用 `allow-firewall.bat`） |
| `realm` 不对（cn/intl） | 面板里切区域；不同区域的账号不通用 |
| 面板密码忘了 | `accounts/settings.json` 里删掉 `panel_password_hash` 后重启 = 回到 `admin` |

---

## 九、构建器的可复现性

`installer/build-portable-win.py`：

- 受管文件清单直接读 `release/portable.txt`（上游定义，60 个文件）
- 运行时用 python.org 官方 **embeddable** 包 `python-3.12.10-embed-amd64.zip`（固定版本+URL）
- 打包时统一换行：`.sh/.command` 强制 LF（避免 Windows 检出 CRLF 导致 `bad interpreter`），
  `.bat` 强制 CRLF，其余 LF
- 输出 `release-manifest.json`（version / root / 受管文件 / runtime 版本 / 受保护目录）
- 时间戳固定，同样输入产出同样 zip

上游原有的 `release/release_tools.py portable` 走 python-build-standalone 的 46MB 运行时，
保留未动；镜像环境下那条下载链路很慢，所以另给了上面这条 python.org 的路。
