#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")

# 加载 .env
if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    source "$ROOT_DIR/.env"
    set +a
else
    echo "[ERROR] .env not found. Run 'make env' first."
    exit 1
fi

ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

echo "Detected OS: $OS, ARCH: $ARCH"

# 映射 arch 到常用名称
case "$ARCH" in
    x86_64)  ARCH_SHORT="amd64" ;;
    aarch64) ARCH_SHORT="arm64" ;;
    armv7l)  ARCH_SHORT="armv7" ;;
    *)       ARCH_SHORT="$ARCH" ;;
esac

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p /usr/local/bin

install_xray() {
    if [ -z "$XRAY_DOWNLOAD_URL" ]; then
        echo "[SKIP] XRAY_DOWNLOAD_URL not set, skipping xray"
        return
    fi
    echo "[xray] Downloading from $XRAY_DOWNLOAD_URL ..."
    cd "$TMPDIR"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o xray.zip "$XRAY_DOWNLOAD_URL"
    else
        wget -q -O xray.zip "$XRAY_DOWNLOAD_URL"
    fi
    unzip -q xray.zip -d xray_extracted
    install -m 755 xray_extracted/xray /usr/local/bin/xray
    mkdir -p /usr/local/etc/xray
    echo "[xray] Installed to /usr/local/bin/xray"
}

install_hy2() {
    if [ -z "$HY2_DOWNLOAD_URL" ]; then
        echo "[SKIP] HY2_DOWNLOAD_URL not set, skipping hysteria"
        return
    fi
    echo "[hysteria] Downloading from $HY2_DOWNLOAD_URL ..."
    cd "$TMPDIR"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o hysteria "$HY2_DOWNLOAD_URL"
    else
        wget -q -O hysteria "$HY2_DOWNLOAD_URL"
    fi
    install -m 755 hysteria /usr/local/bin/hysteria
    mkdir -p /usr/local/etc/hysteria
    echo "[hysteria] Installed to /usr/local/bin/hysteria"
}

install_singbox() {
    if [ -z "$SINGBOX_DOWNLOAD_URL" ]; then
        echo "[SKIP] SINGBOX_DOWNLOAD_URL not set, skipping sing-box"
        return
    fi
    echo "[sing-box] Downloading from $SINGBOX_DOWNLOAD_URL ..."
    cd "$TMPDIR"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o sing-box.tar.gz "$SINGBOX_DOWNLOAD_URL"
    else
        wget -q -O sing-box.tar.gz "$SINGBOX_DOWNLOAD_URL"
    fi
    tar -xzf sing-box.tar.gz
    # sing-box tar 通常解压后目录内有 sing-box 二进制
    SINGBOX_BIN=$(find . -name 'sing-box' -type f | head -n1)
    if [ -z "$SINGBOX_BIN" ]; then
        echo "[ERROR] sing-box binary not found in archive"
        exit 1
    fi
    install -m 755 "$SINGBOX_BIN" /usr/local/bin/sing-box
    mkdir -p /usr/local/etc/sing-box
    echo "[sing-box] Installed to /usr/local/bin/sing-box"
}

install_nginx() {
    if command -v nginx >/dev/null 2>&1; then
        echo "[nginx] Already installed: $(which nginx)"
        return
    fi
    echo "[nginx] Installing via system package manager ..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y nginx
    elif command -v yum >/dev/null 2>&1; then
        yum install -y nginx
    elif command -v apk >/dev/null 2>&1; then
        apk add nginx
    else
        echo "[WARN] Unknown package manager, please install nginx manually"
    fi
}

# 执行安装
install_xray
install_hy2
install_singbox
install_nginx

echo "[DONE] All binaries installed."
