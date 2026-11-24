#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建 Windows 便携包（自带 Python 运行时）。

上游仓库已删除，官方 release 资产再也取不到，这个脚本用 python.org 官方的
embeddable 包重建同样的东西：`python/` 里放一个能直接跑的精简 CPython，
启动脚本 start-wb-proxy.bat 会优先用它，所以目标机不需要装任何 Python。

    python3 installer/build-portable-win.py                 # 产物在 dist/
    python3 installer/build-portable-win.py --no-runtime    # 源码包（目标机需 Python 3.9+）
    python3 installer/build-portable-win.py --runtime-zip python-3.12.10-embed-amd64.zip

受管文件清单来自 release/portable.txt（上游定义），绝不包含 accounts/ 与 usage/。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MANIFEST = os.path.join(ROOT, "release", "portable.txt")
PACKAGE_ROOT = "wb-proxy"

PY_VERSION = "3.12.10"
PY_URL = "https://www.python.org/ftp/python/%s/python-%s-embed-amd64.zip" % (PY_VERSION, PY_VERSION)


def read_managed(path=MANIFEST):
    out = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            out.append(line)
    return out


def source_version():
    """wb_proxy.py 里 server_version = "wb-proxy/x.y.z"（与上游 release_tools.source_version 一致）。"""
    import re
    with open(os.path.join(ROOT, "wb_proxy.py"), "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    m = re.search(r'server_version\s*=\s*"wb-proxy/([^"]+)"', text)
    if not m:
        raise SystemExit("wb_proxy.py 里找不到 server_version")
    return m.group(1)


def normalize(data, name):
    if name.lower().endswith((".sh", ".command")):
        return data.replace(b"\r\n", b"\n"), 0o755
    if name.lower().endswith(".bat"):
        return data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"), 0o755
    if name.lower().endswith((".py", ".json", ".md", ".html", ".txt", "license", ".yml", ".example")):
        return data.replace(b"\r\n", b"\n"), 0o644
    return data.replace(b"\r\n", b"\n"), 0o644


def fetch_runtime(dest_zip, runtime_zip=None):
    if runtime_zip:
        return runtime_zip
    os.makedirs(os.path.dirname(dest_zip), exist_ok=True)
    if not os.path.isfile(dest_zip):
        print("下载 Python %s embeddable: %s" % (PY_VERSION, PY_URL))
        urllib.request.urlretrieve(PY_URL, dest_zip)
    return dest_zip


def build(version, out_path, runtime_zip=None, with_runtime=True, epoch=1704067200):
    files = read_managed()
    missing = [p for p in files if not os.path.isfile(os.path.join(ROOT, p))]
    if missing:
        raise SystemExit("清单里的文件不存在：%s" % ", ".join(missing))

    entries = []
    for name in files:
        with open(os.path.join(ROOT, name), "rb") as fh:
            data = fh.read()
        data, mode = normalize(data, name)
        entries.append(("%s/%s" % (PACKAGE_ROOT, name), data, mode))

    runtime_files = 0
    if with_runtime:
        rz = fetch_runtime(os.path.join(HERE, ".cache", "python-%s-embed-amd64.zip" % PY_VERSION), runtime_zip)
        with zipfile.ZipFile(rz) as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                data = zf.read(info.filename)
                entries.append(("%s/python/%s" % (PACKAGE_ROOT, info.filename), data, 0o755))
                runtime_files += 1

    manifest = {
        "name": "workbuddy2api",
        "version": version,
        "root": PACKAGE_ROOT,
        "files": files,
        "runtime": ({"prefix": "python/", "python": PY_VERSION, "source": PY_URL,
                     "files": runtime_files} if with_runtime else None),
        "protected": ["accounts", "usage"],
        "note": "镜像自 ardeyouxipianyi/workbuddy2api-hub v2.0.0 (d234396)；上游仓库已删除",
    }
    blob = (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")

    import time
    when = time.gmtime(epoch)[:6]
    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data, mode in sorted(entries, key=lambda e: e[0]):
            zi = zipfile.ZipInfo(name, date_time=when)
            zi.external_attr = mode << 16
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.create_system = 3
            zf.writestr(zi, data)
        zi = zipfile.ZipInfo("release-manifest.json", date_time=when)
        zi.external_attr = 0o644 << 16
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.create_system = 3
        zf.writestr(zi, blob)
    return out_path, files, runtime_files


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser(description="构建 WorkBuddy2API Windows 便携包")
    ap.add_argument("--out", default=None)
    ap.add_argument("--runtime-zip", default=None, help="已下载的 embeddable zip")
    ap.add_argument("--no-runtime", action="store_true", help="不塞 python/，产出源码包")
    args = ap.parse_args(argv)

    version = source_version()
    suffix = "portable-win-x64" if not args.no_runtime else "src"
    out = args.out or os.path.join(ROOT, "dist", "workbuddy2api-%s-%s.zip" % (version, suffix))
    path, files, rt = build(version, out, args.runtime_zip, not args.no_runtime)
    size = os.path.getsize(path)
    print("版本      %s" % version)
    print("受管文件  %d" % len(files))
    print("运行时    %s" % ("python %s（%d 个文件）" % (PY_VERSION, rt) if rt else "无"))
    print("产物      %s  (%.1f MB)" % (path, size / 1048576.0))
    print("sha256    %s" % sha256(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
