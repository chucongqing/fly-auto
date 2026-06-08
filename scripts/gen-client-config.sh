#!/bin/bash

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env.client"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env.client file not found!"
  echo "Please run 'make client-env' and configure .env.client first."
  exit 1
fi

# Source the env file
source "$ENV_FILE"

# Resolve per-protocol server addresses (fallback to default SERVER_ADDR)
CLIENT_VLESS_SERVER="${CLIENT_VLESS_SERVER:-$SERVER_ADDR}"
CLIENT_HY2_SERVER="${CLIENT_HY2_SERVER:-$SERVER_ADDR}"
CLIENT_TUIC_SERVER="${CLIENT_TUIC_SERVER:-$SERVER_ADDR}"
CLIENT_ANYTLS_SERVER="${CLIENT_ANYTLS_SERVER:-$SERVER_ADDR}"

# Resolve per-protocol TLS server names (fallback to corresponding server address)
CLIENT_HY2_SERVER_NAME="${CLIENT_HY2_SERVER_NAME:-$CLIENT_HY2_SERVER}"
CLIENT_TUIC_SERVER_NAME="${CLIENT_TUIC_SERVER_NAME:-$CLIENT_TUIC_SERVER}"
CLIENT_ANYTLS_SERVER_NAME="${CLIENT_ANYTLS_SERVER_NAME:-$CLIENT_ANYTLS_SERVER}"

# Make sure config output directory exists
mkdir -p "$ROOT_DIR/client/config"
OUTPUT_FILE="$ROOT_DIR/client/config/config.json"

# Validate at least one protocol is enabled
ENABLED_TAGS=()
if [ "$ENABLE_VLESS" = "true" ]; then ENABLED_TAGS+=("vless"); fi
if [ "$ENABLE_HY2" = "true" ]; then ENABLED_TAGS+=("hy2"); fi
if [ "$ENABLE_TUIC" = "true" ]; then ENABLED_TAGS+=("tuic"); fi
if [ "$ENABLE_ANYTLS" = "true" ]; then ENABLED_TAGS+=("anytls"); fi

if [ ${#ENABLED_TAGS[@]} -eq 0 ]; then
  echo "Error: No protocols enabled. Please enable at least one protocol in .env.client"
  exit 1
fi

# Format join helper
join_by_quotes() {
  local first=1
  for item in "$@"; do
    if [ $first -eq 1 ]; then
      first=0
    else
      echo -n ","
    fi
    echo -n "\"$item\""
  done
}

# Parse DNS servers helper (supports legacy URL and new schemas)
parse_dns_server() {
  local tag="$1"
  local dns_val="$2"
  local detour="$3"
  
  local type=""
  local server=""
  local server_port=""
  local path=""
  
  if [[ "$dns_val" =~ ^(tls|https|quic|h3|tcp|udp)://([^/]+)(/.*)?$ ]]; then
    type="${BASH_REMATCH[1]}"
    local host_port="${BASH_REMATCH[2]}"
    path="${BASH_REMATCH[3]}"
    
    if [ "$path" = "/" ]; then
      path=""
    fi
    
    if [[ "$host_port" =~ ^([^:]+):([0-9]+)$ ]]; then
      server="${BASH_REMATCH[1]}"
      server_port="${BASH_REMATCH[2]}"
    else
      server="$host_port"
    fi
  else
    # Default to udp if no scheme is specified
    type="udp"
    if [[ "$dns_val" =~ ^([^:]+):([0-9]+)$ ]]; then
      server="${BASH_REMATCH[1]}"
      server_port="${BASH_REMATCH[2]}"
    else
      server="$dns_val"
    fi
  fi

  # Build JSON block with proper indentation (6 spaces)
  local json="      {\n        \"tag\": \"$tag\",\n        \"type\": \"$type\",\n        \"server\": \"$server\""
  if [ -n "$server_port" ]; then
    json="$json,\n        \"server_port\": $server_port"
  fi
  if [ -n "$path" ]; then
    json="$json,\n        \"path\": \"$path\""
  fi
  if [ -n "$detour" ]; then
    json="$json,\n        \"detour\": \"$detour\""
  fi
  json="$json\n      }"
  printf "%b" "$json"
}

# 1. Build enabled outbounds JSON array
OUTBOUNDS_LIST=()

# VLESS Reality Outbound
if [ "$ENABLE_VLESS" = "true" ]; then
  OUTBOUNDS_LIST+=("$(cat <<EOF
    {
      "type": "vless",
      "tag": "vless",
      "server": "$CLIENT_VLESS_SERVER",
      "server_port": $CLIENT_VLESS_PORT,
      "uuid": "$CLIENT_VLESS_UUID",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$CLIENT_VLESS_SERVER_NAME",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "$CLIENT_VLESS_REALITY_PUBLIC_KEY",
          "short_id": "$CLIENT_VLESS_REALITY_SHORT_ID"
        }
      }
    }
EOF
)")
fi

# Hysteria 2 Outbound
if [ "$ENABLE_HY2" = "true" ]; then
  OUTBOUNDS_LIST+=("$(cat <<EOF
    {
      "type": "hysteria2",
      "tag": "hy2",
      "server": "$CLIENT_HY2_SERVER",
      "server_port": $CLIENT_HY2_PORT,
      "password": "$CLIENT_HY2_PASSWORD",
      "tls": {
        "enabled": true,
        "server_name": "$CLIENT_HY2_SERVER_NAME",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        }
      }
    }
EOF
)")
fi

# TUIC Outbound
if [ "$ENABLE_TUIC" = "true" ]; then
  OUTBOUNDS_LIST+=("$(cat <<EOF
    {
      "type": "tuic",
      "tag": "tuic",
      "server": "$CLIENT_TUIC_SERVER",
      "server_port": $CLIENT_TUIC_PORT,
      "uuid": "$CLIENT_TUIC_UUID",
      "password": "$CLIENT_TUIC_PASSWORD",
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "server_name": "$CLIENT_TUIC_SERVER_NAME",
        "alpn": [
          "h3"
        ],
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        }
      }
    }
EOF
)")
fi

# AnyTLS Outbound
if [ "$ENABLE_ANYTLS" = "true" ]; then
  OUTBOUNDS_LIST+=("$(cat <<EOF
    {
      "type": "anytls",
      "tag": "anytls",
      "server": "$CLIENT_ANYTLS_SERVER",
      "server_port": $CLIENT_ANYTLS_PORT,
      "username": "$CLIENT_ANYTLS_USERNAME",
      "password": "$CLIENT_ANYTLS_PASSWORD",
      "tls": {
        "enabled": true,
        "server_name": "$CLIENT_ANYTLS_SERVER_NAME",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        }
      }
    }
EOF
)")
fi

# Selectors / URL Test Outbounds
SELECTOR_TAGS=()
SELECTOR_TAGS+=("auto")
for tag in "${ENABLED_TAGS[@]}"; do
  SELECTOR_TAGS+=("$tag")
done

# Resolve default outbound tag
DEFAULT_TAG="auto"
for tag in "${ENABLED_TAGS[@]}"; do
  if [ "$DEFAULT_OUTBOUND" = "$tag" ]; then
    DEFAULT_TAG="$tag"
    break
  fi
done

# Build auto (urltest) and proxy (selector) outbounds
AUTO_OUTBOUNDS_CSV=$(join_by_quotes "${ENABLED_TAGS[@]}")
SELECTOR_OUTBOUNDS_CSV=$(join_by_quotes "${SELECTOR_TAGS[@]}")

PROXY_OUTBOUNDS="$(cat <<EOF
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": [
        $SELECTOR_OUTBOUNDS_CSV
      ],
      "default": "$DEFAULT_TAG"
    },
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": [
        $AUTO_OUTBOUNDS_CSV
      ],
      "url": "https://cp.cloudflare.com/generate_204",
      "interval": "3m0s",
      "tolerance": 50
    }
EOF
)"

# WARP Outbound (if enabled)
WARP_OUTBOUND=""
if [ "$ENABLE_WARP" = "true" ]; then
  WARP_OUTBOUND=",
    {
      "type": "socks",
      "tag": "warp",
      "server": "$CLIENT_WARP_SERVER",
      "server_port": $CLIENT_WARP_PORT
    }"
fi

# Standard Outbounds
STANDARD_OUTBOUNDS=",
    {
      \"type\": \"direct\",
      \"tag\": \"direct\"
    },
    {
      \"type\": \"block\",
      \"tag\": \"block\"
    },
    {
      \"type\": \"dns\",
      \"tag\": \"dns-out\"
    }"

# Join all outbounds
ALL_OUTBOUNDS_JSON=""
for ob in "${OUTBOUNDS_LIST[@]}"; do
  if [ -n "$ALL_OUTBOUNDS_JSON" ]; then
    ALL_OUTBOUNDS_JSON="$ALL_OUTBOUNDS_JSON,
$ob"
  else
    ALL_OUTBOUNDS_JSON="$ob"
  fi
done

# WARP Routing rules (if enabled)
WARP_ROUTE_RULE=""
if [ "$ENABLE_WARP" = "true" ]; then
  WARP_ROUTE_RULE="{
        \"domain_suffix\": [
          \"google.com\",
          \"googleapis.com\",
          \"googleusercontent.com\",
          \"gstatic.com\",
          \"gvt1.com\",
          \"gvt2.com\",
          \"gvt3.com\",
          \"ggpht.com\",
          \"android.com\",
          \"openai.com\",
          \"chatgpt.com\",
          \"gemini.google.com\"
        ],
        \"action\": \"route\",
        \"outbound\": \"warp\"
      },"
fi

# Parse DNS servers
REMOTE_DNS_JSON=$(parse_dns_server "remote-dns" "$REMOTE_DNS" "proxy")
LOCAL_DNS_JSON=$(parse_dns_server "local-dns" "$LOCAL_DNS" "direct")

# Build config.json
cat <<EOF > "$OUTPUT_FILE"
{
  "log": {
    "level": "info"
  },
  "dns": {
    "servers": [
$REMOTE_DNS_JSON,
$LOCAL_DNS_JSON
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "local-dns"
      },
      {
        "clash_mode": "direct",
        "server": "local-dns"
      },
      {
        "clash_mode": "global",
        "server": "remote-dns"
      },
      {
        "domain_suffix": [
          "cn",
          "local",
          "lan"
        ],
        "server": "local-dns"
      },
      {
        "rule_set": [
          "geosite-cn"
        ],
        "server": "local-dns"
      }
    ],
    "final": "remote-dns",
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "$CLIENT_MIXED_LISTEN",
      "listen_port": $CLIENT_MIXED_PORT
    }
  ],
  "outbounds": [
    $PROXY_OUTBOUNDS,
    $ALL_OUTBOUNDS_JSON$WARP_OUTBOUND$STANDARD_OUTBOUNDS
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "type": "logical",
        "mode": "or",
        "rules": [
          {
            "port": 53
          },
          {
            "protocol": "dns"
          }
        ],
        "action": "hijack-dns"
      },
      {
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "clash_mode": "direct",
        "action": "route",
        "outbound": "direct"
      },
      {
        "clash_mode": "global",
        "action": "route",
        "outbound": "proxy"
      },
      $WARP_ROUTE_RULE
      {
        "domain_suffix": [
          "cn",
          "local",
          "lan"
        ],
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geosite-cn"
        ],
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geoip-cn"
        ],
        "action": "route",
        "outbound": "direct"
      }
    ],
    "rule_set": [
      {
        "tag": "geosite-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        "download_detour": "proxy"
      },
      {
        "tag": "geoip-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "download_detour": "proxy"
      }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
EOF

# ============================================================
# Generate Hysteria 2 client config (standalone client mode)
# ============================================================
HY2_CONFIG_DIR="$ROOT_DIR/client/hy2-config"
mkdir -p "$HY2_CONFIG_DIR"
HY2_OUTPUT_FILE="$HY2_CONFIG_DIR/config.yaml"

cat <<EOF > "$HY2_OUTPUT_FILE"
server: "$CLIENT_HY2_SERVER:$CLIENT_HY2_PORT"
auth: "$CLIENT_HY2_PASSWORD"
socks5:
  listen: "0.0.0.0:$CLIENT_HY2_SOCKS5_PORT"
http:
  listen: "0.0.0.0:$CLIENT_HY2_HTTP_PORT"
tls:
  sni: "$CLIENT_HY2_SERVER_NAME"
EOF

echo "Client config generated successfully at: $OUTPUT_FILE"
echo "Hysteria 2 client config generated at: $HY2_OUTPUT_FILE"

# Validate JSON syntax
if command -v jq >/dev/null 2>&1; then
  if ! jq empty "$OUTPUT_FILE" >/dev/null 2>&1; then
    echo "Error: $OUTPUT_FILE is not valid JSON"
    exit 1
  fi
  echo "JSON validation passed."
else
  echo "Warning: jq not found, skipping JSON validation"
fi

