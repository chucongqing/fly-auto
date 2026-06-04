# Fly-Auto

一键自动化部署多协议代理服务。基于 **Xray (VLESS+REALITY)**、**Hysteria 2**、**sing-box (TUIC)** 和 **Nginx**，支持 **Docker Compose** 和 **systemd** 两种部署模式，适合在自有域名和 Linux 服务器上快速搭建安全、隐蔽的代理服务。

- **Docker 模式**：适合标准服务器，隔离性好，易于管理。
- **systemd 模式**：适合**低配 VPS** 或无法安装 Docker 的环境，直接以系统服务运行，资源占用更低。

---

## 架构概览

```
┌────────────────────────────────────────────────────────────┐
│                        客户端                               │
│  (V2RayN / Nekoray / Shadowrocket / Surge / Streisand ...)│
└──────────┬────────────────────┬────────────────────────────┘
           │                    │
    VLESS+REALITY       Hysteria 2 / TUIC
    (端口 443)          (端口 10443 / 20443)
           │                    │
┌──────────┴────────────────────┴────────────────────────────┐
│                      Linux 服务器                           │
│  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌────────────┐   │
│  │  Nginx  │  │  Xray   │  │ Hysteria │  │  sing-box  │   │
│  │  :80    │  │  :443   │  │  :10443  │  │  :20443    │   │
│  │ACME/跳转│  │VLESS/REALITY│  │  协议    │  │   TUIC    │   │
│  └─────────┘  └─────────┘  └──────────┘  └────────────┘   │
│  SSL 证书统一挂载到 /etc/ssl (acme.sh 签发)                 │
└────────────────────────────────────────────────────────────┘
```

---

## 包含的服务

| 服务 | 协议 | 默认端口 | 用途 |
|------|------|---------|------|
| **Nginx** | HTTP | 80 | ACME 验证 + HTTP → HTTPS 跳转 |
| **Xray** | VLESS + REALITY | 443 | 主要代理入口，伪装成目标网站 |
| **Hysteria 2** | UDP / quic | 10443 | 高速 UDP 代理，抗审查能力强 |
| **sing-box** | TUIC | 20443 | 基于 QUIC 的代理，低延迟 |

---

## 前置要求

- 一台 Linux 服务器（推荐 Ubuntu / Debian / CentOS / Alpine）
- 一个自己的域名，并已解析到服务器 IP
- 已安装 `make` 和 `envsubst` (通常 `apt install gettext-base`)
- 已安装 [acme.sh](https://github.com/acmesh-official/acme.sh) 用于自动签发 SSL 证书

### 二选一（两种模式只需要满足其一）

| 模式 | 额外依赖 |
|------|---------|
| **Docker 模式** | Docker + Docker Compose |
| **systemd 模式** | systemd + curl/wget（用于下载二进制） |

### 安装 acme.sh

```bash
curl https://get.acme.sh | sh -s email=my@example.com
```

> 默认安装在 `~/.acme.sh`。本文档假设使用此路径。

---

## 目录结构

```
.
├── .env                    # 你的配置（从 .env.example 复制）
├── Makefile                # 一键命令
├── readme.md
├── scripts/
│   ├── setup.sh            # 创建证书目录
│   ├── issue_cert.sh       # 手动签发证书（备用）
│   ├── reload.sh           # Docker 模式：重启所有容器
│   ├── install-bin.sh      # systemd 模式：下载二进制
│   ├── install-systemd.sh  # systemd 模式：安装系统服务
│   └── uninstall-systemd.sh # systemd 模式：卸载系统服务
├── server/                 # Docker 模式配置文件模板
│   ├── nginx/
│   ├── xray/
│   ├── hy2/
│   └── sing-box/
└── systemd/                # systemd service 模板
    ├── nginx.service.template
    ├── xray.service.template
    ├── hy2.service.template
    └── sing-box.service.template
```

---

## 快速开始

两种模式共享相同的 `.env` 配置和证书流程，只是在启动服务时选择不同的命令。

### 1. 初始化

```bash
make init      # 创建必要的目录
make env       # 生成 .env 文件，按需修改
```

编辑 `.env`，填写你的域名、密码、UUID 等信息。关键变量示例：

```env
MYSITE=www.your-domain.com

# Xray REALITY
XRAY_UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
XRAY_REALITY_PRIVATE_KEY=xxxxx
XRAY_REALITY_MLDSA65_SEED=xxxxx
XRAY_TARGET=www.microsoft.com:443

# Hysteria 2
HY2_PASSWORD=your-strong-password

# sing-box TUIC
SINGBOX_TUIC_UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SINGBOX_TUIC_PASSWORD=your-strong-password
```

生成配置文件：

```bash
make template    # 渲染所有配置文件
```

申请 SSL 证书（两种模式都需要）：

```bash
make up-nginx    # 启动 Nginx（用于 ACME HTTP-01 验证）
make issue_cert  # 申请证书
make install_cert # 安装证书并设置自动续期
```

> **注意**：如果你使用 systemd 模式且系统没有 Docker，`make up-nginx` 需要换成 `make start-nginx`（见下方 systemd 模式说明）。

---

## Docker 模式（推荐）

适合有 Docker 环境的标准服务器。

```bash
# 启动全部服务
make up

# 或单独控制
make up-nginx     # 启动 Nginx
make up-xray      # 启动 Xray
make up-hy2       # 启动 Hysteria 2
make up-singbox   # 启动 sing-box
```

查看状态：

```bash
docker ps
```

---

## systemd 模式（无 Docker）

适合**低配 VPS**、OpenVZ 容器、或任何无法/不想安装 Docker 的环境。所有服务直接以系统服务运行，资源占用更低。

### 配置二进制下载地址

编辑 `.env`，填写各组件的二进制下载 URL（已从 `.env.example` 预填了常见值）：

```env
# Xray: .zip 格式
XRAY_DOWNLOAD_URL=https://github.com/XTLS/Xray-core/releases/download/v26.1.13/Xray-linux-64.zip

# Hysteria 2: 单个二进制
HY2_DOWNLOAD_URL=https://github.com/apernet/hysteria/releases/download/app/v2.9.2/hysteria-linux-amd64

# sing-box: .tar.gz 格式
SINGBOX_DOWNLOAD_URL=https://github.com/Sagernet/sing-box/releases/download/v1.13.12/sing-box-1.13.12-linux-amd64.tar.gz
```

> 如果你不需要某个服务，将其对应的 `*_DOWNLOAD_URL` 留空，安装脚本会自动跳过。

### 安装并启动

```bash
# 1. 下载并安装所有二进制（nginx 会自动用包管理器安装）
sudo make install-bin

# 2. 安装 systemd service 文件并启用开机自启
sudo make install-systemd

# 3. 将配置文件复制到 systemd 服务使用的系统路径
sudo make sys-template

# 4. 启动所有服务
sudo make start
```

等价的一键执行：

```bash
sudo make install-bin install-systemd sys-template start
```

### 管理服务

```bash
# 全部服务
sudo make start        # 启动
sudo make stop         # 停止
sudo make restart      # 重启
sudo make status       # 查看状态

# 单个服务
sudo make start-nginx      # 启动 Nginx
sudo make stop-nginx       # 停止 Nginx
sudo make restart-nginx    # 重启 Nginx
sudo make start-xray       # 启动 Xray
sudo make stop-xray        # 停止 Xray
sudo make restart-xray     # 重启 Xray
sudo make start-hy2        # 启动 Hysteria 2
sudo make stop-hy2         # 停止 Hysteria 2
sudo make restart-hy2      # 重启 Hysteria 2
sudo make start-singbox    # 启动 sing-box
sudo make stop-singbox     # 停止 sing-box
sudo make restart-singbox  # 重启 sing-box
```

### 卸载 systemd 服务

```bash
sudo make uninstall-systemd
sudo make clear-systemd    # 清除复制到系统路径的配置文件
```

---

## 配置详解

### `.env` 变量说明

| 变量 | 说明 | 示例 |
|------|------|------|
| `MYSITE` | 你的域名 | `www.example.com` |
| `XRAY_UUID` | VLESS 用户 UUID | 用 `xray uuid` 生成 |
| `XRAY_VLESS_PORT` | VLESS 入站端口 | `443` |
| `XRAY_TARGET` | REALITY 伪装目标 | `www.microsoft.com:443` |
| `XRAY_SERVERNAMES` | REALITY 允许 SNI | `"www.microsoft.com","microsoft.com"` |
| `XRAY_SHORTIDS` | REALITY shortId（可多个） | `"aabbccdd","ffee5678"` |
| `XRAY_REALITY_PRIVATE_KEY` | REALITY 私钥 | 用 `xray x25519` 生成 |
| `XRAY_REALITY_MLDSA65_SEED` | REALITY ML-DSA65 种子 | 用 `xray x25519` 生成 |
| `HY2_ADDR` | Hysteria 2 监听地址 | `:10443` |
| `HY2_PASSWORD` | Hysteria 2 密码 | — |
| `SINGBOX_TUIC_PORT` | TUIC 端口 | `20443` |
| `SINGBOX_TUIC_UUID` | TUIC 用户 UUID | — |
| `SINGBOX_TUIC_PASSWORD` | TUIC 密码 | — |
| `HY2_WARP_ADDR` | Hysteria 2 WARP SOCKS5 地址 | `127.0.0.1:40000` |
| `SINGBOX_WARP_SERVER` | sing-box WARP SOCKS5 服务器 | `127.0.0.1` |
| `SINGBOX_WARP_PORT` | sing-box WARP SOCKS5 端口 | `40000` |
| `XRAY_DOWNLOAD_URL` | Xray 二进制下载地址（systemd） | `.zip` 格式 |
| `HY2_DOWNLOAD_URL` | Hysteria 2 二进制下载地址（systemd） | 单个二进制 |
| `SINGBOX_DOWNLOAD_URL` | sing-box 二进制下载地址（systemd） | `.tar.gz` 格式 |

### 生成 Xray REALITY 密钥

```bash
# 如果你已安装 xray 二进制
xray x25519

# 或从 Docker 运行（Docker 模式）
docker run --rm ghcr.io/xtls/xray-core x25519
```

输出中的 `Private key` 填入 `XRAY_REALITY_PRIVATE_KEY`，`Public key` 填入客户端配置。

---

## Makefile 命令速查

### 通用命令

| 命令 | 作用 |
|------|------|
| `make init` | 创建证书、SSL 目录 |
| `make env` | 从 `.env.example` 复制出 `.env` |
| `make template` | 渲染所有配置文件（Docker 路径） |
| `make issue_cert` | 用 acme.sh 申请 Let's Encrypt 证书 |
| `make install_cert` | 安装证书到 `/etc/ssl`，并设置续期钩子 |
| `make clear` | 清除 Docker 模式的配置文件和 `.env` |
| `make clear-systemd` | 清除 systemd 模式复制到系统路径的配置 |

### Docker 模式

| 命令 | 作用 |
|------|------|
| `make up` | 重启所有 Docker 容器 |
| `make up-nginx` | 仅启动 Nginx 容器 |
| `make up-xray` | 仅启动 Xray 容器 |
| `make up-hy2` | 仅启动 Hysteria 2 容器 |
| `make up-singbox` | 仅启动 sing-box 容器 |
| `make restart-docker-nginx` | 仅重启 Nginx 容器（应用配置变更） |
| `make restart-docker-xray` | 仅重启 Xray 容器（应用配置变更） |
| `make restart-docker-hy2` | 仅重启 Hysteria 2 容器（应用配置变更） |
| `make restart-docker-singbox` | 仅重启 sing-box 容器（应用配置变更） |

### systemd 模式

| 命令 | 作用 |
|------|------|
| `make install-bin` | 下载并安装所有二进制到 `/usr/local/bin/` |
| `make install-systemd` | 安装并启用所有 systemd service |
| `make uninstall-systemd` | 停止、禁用并删除所有 systemd service |
| `make sys-template` | 复制配置文件到 `/usr/local/etc/` 和 `/etc/nginx/conf.d/` |
| `make start` | 启动所有 systemd 服务 |
| `make stop` | 停止所有 systemd 服务 |
| `make restart` | 重启所有 systemd 服务 |
| `make status` | 查看所有 systemd 服务状态 |
| `make start-nginx` / `stop-nginx` / `restart-nginx` | 管理 Nginx |
| `make start-xray` / `stop-xray` / `restart-xray` | 管理 Xray |
| `make start-hy2` / `stop-hy2` / `restart-hy2` | 管理 Hysteria 2 |
| `make start-singbox` / `stop-singbox` / `restart-singbox` | 管理 sing-box |

---

## 解锁 Google Gemini / ChatGPT（WARP 分流）

如果你的 VPS IP 被 Google 标记为"送中"（访问 Gemini 提示地区不支持，或 Google 搜索定位显示为国内），可以通过 **Cloudflare WARP** 对特定域名流量进行局部代理分流，而不影响普通流量的直连速度。

### 原理

1. 在 VPS 本地运行 WARP（SOCKS5 模式，默认端口 `40000`）。
2. Hysteria 2 开启 **协议嗅探 (Protocol Sniffing)**，从 TLS SNI 中还原域名，解决客户端以 IP 连接导致的域名分流失效问题。
3. 通过 **ACL 规则**，只将 Google / Gemini / OpenAI 相关流量转发给本地 WARP；其余流量仍然直连。

### 配置说明

项目模板已内置相关配置，运行 `make template` 后会自动生成：

**Hysteria 2**

- **`[sniff]`** 段：启用 DPI，将 IP 请求还原为域名请求。
- **`[[outbounds]]`** 段：定义 `direct_out`（直连）和 `warp_proxy`（SOCKS5 到 WARP）。
- **`[acl]`** 段：按域名后缀分流。

> **ACL 语法陷阱**：Hysteria 2 的语法是 `outbound_name(matcher)`，**不是** `outbound(matcher, outbound_name)`。

**sing-box**

- **`route.rules`** 中第一条 `{ "action": "sniff" }`：启用协议嗅探，从 TLS SNI 还原域名。
- **`outbounds`** 中添加 `{ "type": "socks", "tag": "warp", ... }`：SOCKS5 出站到本地 WARP。
- **`route.rules`** 后续规则通过 `domain_suffix` 匹配 Google / OpenAI 域名，走 `"outbound": "warp"`。
- **`route.final": "direct"`**：未命中规则的流量默认直连。

> sing-box 的路由规则按数组**顺序匹配**，`sniff` 必须放在第一条，否则域名分流失效。

### 安装 WARP（手动）

在 VPS 上执行以下命令安装 Cloudflare WARP 并启用代理模式：

```bash
# 安装
wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh

# 在菜单中选择：5. 安装 CloudFlare Client 并设置为 Proxy 模式
# 接受条款时输入 y，免费版即可，无需绑定自己的账号

# 验证状态
warp-cli status          # 应显示 Status update: Connected

# 测试 SOCKS5 代理
curl -I --socks5-hostname 127.0.0.1:40000 https://www.google.com
```

### 排查

| 现象 | 可能原因 | 解决 |
|------|---------|------|
| Gemini 仍提示地区不支持 | WARP 未运行或路由规则未生效 | 检查 `warp-cli status` 和对应服务日志 |
| 客户端连接后全是 IP 请求 | 未开启 sniff | Hysteria 确认 `[sniff] enable = true`；sing-box 确认 `route.rules` 第一条为 `{ "action": "sniff" }` |
| Hysteria 启动报错 `outbound not found` | ACL 语法错误 | 检查是否为 `warp_proxy(suffix:...)` 而非 `outbound(..., warp_proxy)` |
| sing-box 日志显示域名未匹配到 warp | sniff 顺序不对 | 确认 `sniff` 规则在 `domain_suffix` 规则之前 |

查看实时日志：

```bash
# Hysteria 2 — Docker 模式
docker logs -f hy2

# Hysteria 2 — systemd 模式
journalctl -u hy2 -f

# sing-box — Docker 模式
docker logs -f sing-box

# sing-box — systemd 模式
journalctl -u sing-box -f
```

---

## 常见问题

### Docker 容器无法绑定 443 端口

非 root 容器绑定低端口需要：

```bash
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
```

永久生效请写入 `/etc/sysctl.conf`，然后执行 `sysctl -p`。

> systemd 模式下服务以 root 运行，不存在此问题。

### 证书续期

`make install_cert` 已经通过 `--reloadcmd` 把重启脚本注册到 acme.sh 中，证书续期后会自动重载所有服务，无需手动干预。

- **Docker 模式**：续期后执行 `./scripts/reload.sh`
- **systemd 模式**：续期后执行 `systemctl restart nginx xray hy2 sing-box`

### 修改配置后生效

**Docker 模式**：

只改了单个服务的配置（例如 Hysteria 2）：

```bash
make template              # 重新生成配置（ harmless，不影响运行中的服务）
make restart-docker-hy2    # 只重启 Hysteria 2 容器，应用新配置
```

如果同时修改了多个服务，或者不确定哪些改了，可以直接全部重启：

```bash
make template
make up
```

**systemd 模式**：

```bash
make template
make sys-template
make restart
```

### 如何在同一台机器上混用两种模式？

不建议在同一台机器上同时运行 Docker 和 systemd 模式的相同服务（端口会冲突）。你可以：

- 只用其中一种模式
- 或选择性地只启用部分服务，例如 Docker 运行 Xray，systemd 运行 Hysteria 2

---

## 安全提示

- 不要将 `.env` 和生成的配置文件提交到 Git，项目已预置 `.gitignore`
- 定期更新各组件版本（Docker 模式改 `*_IMAGE`，systemd 模式改 `*_DOWNLOAD_URL`）
- 使用强密码和随机 UUID，避免使用示例中的默认值
- 建议开启服务器的防火墙，只开放必要的端口（80, 443, 10443, 20443 等）
- systemd 模式下服务以 `root` 运行（需要绑定 443 等特权端口），生产环境可考虑使用 `CapabilityBoundingSet` 进一步限制权限

---

## License

MIT
