
---

# 📝 笔记：VPS 部署 Hysteria 2 + WARP 解锁 Gemini 网页端

## 1. 问题背景
*   **现象**：访问网页版 Gemini 提示地区不支持，Google 搜索页面底部定位显示为 `中国杭州`（即使 VPS 物理上在美国）。
*   **原因**：**谷歌 IP 送中（IP Geolocation Redirection）**。由于该机房 IP 长期被国内用户连接或进行中文搜索，被谷歌的算法判定并标记为中国大陆 IP，导致不支持 Gemini。

---

## 2. 核心架构设计
为了不影响 VPS 本身的速度，采用**“局部代理分流”**方案：
*   在 VPS 本地搭建 **Cloudflare WARP (SOCKS5 代理模式，端口 `40000`)**。
*   通过 Hysteria 2 的 **ACL 规则**，只将 Google/Gemini/OpenAI 相关的流量转发给本地 WARP 代理出站；普通流量依然使用 VPS 本地网卡直接发送。

---

## 3. 调试过程中的关键问题与修复

### 🚫 问题一：Hysteria 2 ACL 语法配置报错
*   **报错日志**：`FATAL failed to load server config {"error": "invalid config: acl.inline: error at line 1: outbound outbound not found"}`
*   **原因**：混淆了旧版语法或通用占位符。在 Hysteria 2 中，**自定义出站的名字直接就是 ACL 规则中的“函数/动作名”**。
*   **修正前**：`outbound(suffix:google.com, warp_proxy)`
*   **修正后**：`warp_proxy(suffix:google.com)`

### 🚫 问题二：客户端以 IP 连接，导致域名分流规则失效
*   **现象**：配置完成后，谷歌定位依旧显示在杭州。查看 Hysteria 2 日志，发现请求全是纯 IP（如 `reqAddr: "34.54.84.110:443"`）而不是域名。
*   **原因**：本地 Windows 客户端（尤其是开启了 TUN 模式时）在本地直接解析了 DNS，将 IP 发给服务端。服务端无法感知域名，导致配置的 `suffix:google.com` 域名分流失效，全部回退到默认直连。
*   **解决方案**：开启 Hysteria 2 服务端的 **“协议嗅探” (Protocol Sniffing)**。通过在服务端进行 DPI（深度包检测）从加密连接（TLS SNI）中强行提取出原始域名，并将 IP 请求还原为域名请求，从而精准匹配分流规则。

---

## 4. 最终完美配置文件参考 (`config.toml`)

```toml
# 监听端口
listen = ":8440"

# TLS 证书配置
[tls]
cert = "/etc/v2ray/dog.crt"
key = "/etc/v2ray/dog.key"

# 认证配置
[auth]
type = "password"
password = "your password"

# 伪装网页配置
[masquerade]
type = "proxy"

[masquerade.proxy]
url = "https://www.bing.com/"
rewriteHost = true


# ==================== 新增：协议嗅探 ====================
[sniff]
enable = true
timeout = "2s"
rewriteDomain = true  # 设为 true，强行把 IP 还原为域名发送给出站代理（这能让 WARP 重新解析出最快的国外 IP）

# ==================== 出站定义 ====================

# 1. 默认直连出站（必须写在第一个，作为默认出站）
[[outbounds]]
name = "direct_out"
type = "direct"

# 2. WARP 本地 SOCKS5 出站
[[outbounds]]
name = "warp_proxy"
type = "socks5"
[outbounds.socks5]
addr = "127.0.0.1:40000"

# ==================== 分流规则 ====================
# ACL 语法: 出站名称(地址[, 协议/端口])
# 注意: 不是 outbound(地址, 出站名)，而是 出站名(地址)
[acl]
inline = [
  # 谷歌和 Gemini 相关域名，走 warp_proxy 出站
  "warp_proxy(suffix:google.com)",
  "warp_proxy(suffix:gemini.google.com)",
  "warp_proxy(suffix:googleapis.com)",
  "warp_proxy(suffix:googleusercontent.com)",
  "warp_proxy(suffix:gstatic.com)",

  # 顺便解锁一下 ChatGPT (可选)
  "warp_proxy(suffix:openai.com)",
  "warp_proxy(suffix:chatgpt.com)",

  # 其它所有流量默认走直连
  "direct_out(all)"
]
```

---

## 5. 常用运维排查指令
*   **检查本地 WARP 运行状态**：`warp-cli status`
*   **检查本地 WARP 代理是否畅通**：`curl -I --socks5-hostname 127.0.0.1:40000 https://www.google.com`
*   **重启 Hysteria 2 服务**：`systemctl restart hy2`
*   **实时监视 Hysteria 2 日志**：`journalctl -u hy2 -f`



## WARP 客户端安装与配置步骤

1. **运行 WARP 安装一键脚本（使用最新的 GitLab 源）**： 在 VPS 上运行以下命令：
    
    bash
    
    ```
    wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh
    ```
1. **选择代理模式**： 在弹出的交互菜单中，选择：
    
    > **`5. 安装 CloudFlare Client 并设置为 Proxy 模式 (bash menu.sh c)`**
    
    - _注：如果提示接受服务条款，输入 `y`。若无特殊需求，全程直接选择使用**免费版**即可（无需绑定自己的账号）。_
2. **验证 WARP 是否正常工作**：
    
    - **检查运行状态**（应该显示 `Status update: Connected`）：
        
        bash
        
        warp-cli status
        
    - **通过本地 SOCKS5 端口测试访问谷歌**（应该成功返回 HTTP 200，并显示 Cloudflare 的美国 IP）：
        
        bash
        
        `curl -I --socks5-hostname 127.0.0.1:40000 https://www.google.com`
