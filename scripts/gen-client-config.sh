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

# 1. Build enabled outbounds JSON array
OUTBOUNDS_LIST=()

# VLESS Reality Outbound
if [ "$ENABLE_VLESS" = "true" ]; then
  OUTBOUNDS_LIST+=("$(cat <<EOF
    {
      "type": "vless",
      "tag": "vless",
      "server": "$SERVER_ADDR",
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
      "server": "$SERVER_ADDR",
      "server_port": $CLIENT_HY2_PORT,
      "password": "$CLIENT_HY2_PASSWORD",
      "tls": {
        "enabled": true,
        "server_name": "$SERVER_ADDR",
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
      "server": "$SERVER_ADDR",
      "server_port": $CLIENT_TUIC_PORT,
      "uuid": "$CLIENT_TUIC_UUID",
      "password": "$CLIENT_TUIC_PASSWORD",
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "server_name": "$SERVER_ADDR",
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
      "server": "$SERVER_ADDR",
      "server_port": $CLIENT_ANYTLS_PORT,
      "username": "$CLIENT_ANYTLS_USERNAME",
      "password": "$CLIENT_ANYTLS_PASSWORD",
      "tls": {
        "enabled": true,
        "server_name": "$SERVER_ADDR",
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
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
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
          \"openai.com\",
          \"chatgpt.com\",
          \"gemini.google.com\"
        ],
        \"action\": \"route\",
        \"outbound\": \"warp\"
      },"
fi

# Build config.json
cat <<EOF > "$OUTPUT_FILE"
{
  "log": {
    "level": "info"
  },
  "dns": {
    "servers": [
      {
        "tag": "remote-dns",
        "address": "$REMOTE_DNS",
        "detour": "proxy"
      },
      {
        "tag": "local-dns",
        "address": "$LOCAL_DNS",
        "detour": "direct"
      },
      {
        "tag": "block-dns",
        "address": "rcode://success"
      }
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
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "$TUN_INTERFACE",
      "address": [
        "$TUN_IPV4"
      ],
      "auto_route": true,
      "strict_route": true,
      "stack": "system",
      "sniff": true,
      "sniff_override_destination": true
    }
  ],
  "outbounds": [
    $PROXY_OUTBOUNDS,
    $ALL_OUTBOUNDS_JSON$WARP_OUTBOUND$STANDARD_OUTBOUNDS
  ],
  "route": {
    "rules": [
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

echo "Client config generated successfully at: $OUTPUT_FILE"
