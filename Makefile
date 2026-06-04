
# assume we have already install acme.sh
# 获取 Makefile 的完整路径（包含文件名）
MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))

# 获取 Makefile 所在的目录路径（不包含文件名）
CUR_DIR := $(patsubst %/,%,$(dir $(MKFILE_PATH)))

-include .env
export

init:
	-mkdir -p /var/www/cert
	-mkdir -p /etc/ssl
	chmod +x $(CUR_DIR)/scripts/reload.sh

env:
	-mkdir -p /var/www/cert
	cp .env.example .env

clear:
	rm -rf server/hy2/config/config.toml
	rm -rf server/nginx/conf/acme.conf
	rm -rf server/xray/config/config.json
	rm -rf server/sing-box/config/config.json
	rm -rf .env

clear-systemd:
	rm -rf /usr/local/etc/xray/config.json
	rm -rf /usr/local/etc/hysteria/config.toml
	rm -rf /usr/local/etc/sing-box/config.json
	rm -f /etc/nginx/conf.d/acme.conf

# 自动从 .env 中提取所有变量名并拼接成 $VAR1,$VAR2 的格式
VARS_EXTRACTED := $(shell grep -v '^#' .env | cut -d= -f1 | sed 's/^/$$/' | paste -sd, -)

template:
	-mkdir -p server/hy2/config server/nginx/conf server/xray/config server/sing-box/config
	envsubst '$(VARS_EXTRACTED)' < server/hy2/config/config.toml.template > server/hy2/config/config.toml
	envsubst '$(VARS_EXTRACTED)' < server/nginx/acme.conf.template > server/nginx/conf/acme.conf
	envsubst '$(VARS_EXTRACTED)' < server/xray/config/config.json.template > server/xray/config/config.json
	envsubst '$(VARS_EXTRACTED)' < server/sing-box/config/config.json.template > server/sing-box/config/config.json

issue_cert:
	~/.acme.sh/acme.sh --issue --force \
	  -d "$(MYSITE)" \
	  --keylength ec-256 \
	  -w /var/www/cert \
	  --server letsencrypt

install_cert:
	- mkdir -p /etc/ssl
	~/.acme.sh/acme.sh --install-cert \
	  -d "$(MYSITE)" \
	  --keylength ec-256 \
	  --fullchain-file /etc/ssl/cert.pem \
	  --key-file /etc/ssl/key.pem \
	  --reloadcmd "$(CUR_DIR)/scripts/reload.sh"

up:
	$(CUR_DIR)/scripts/reload.sh

up-nginx:
	docker compose -f server/nginx/docker-compose.yml up -d

up-hy2:
	docker compose -f server/hy2/docker-compose.yml up -d

up-xray:
	docker compose -f server/xray/docker-compose.yml up -d

up-singbox:
	docker compose -f server/sing-box/docker-compose.yml up -d

# Restart individual Docker containers to apply config changes
restart-docker-nginx:
	docker compose -f server/nginx/docker-compose.yml restart

restart-docker-hy2:
	docker compose -f server/hy2/docker-compose.yml restart

restart-docker-xray:
	docker compose -f server/xray/docker-compose.yml restart

restart-docker-singbox:
	docker compose -f server/sing-box/docker-compose.yml restart

# =============================================================================
# systemd targets (for low-end VPS without Docker)
# =============================================================================

install-bin:
	chmod +x $(CUR_DIR)/scripts/install-bin.sh
	$(CUR_DIR)/scripts/install-bin.sh

install-systemd:
	chmod +x $(CUR_DIR)/scripts/install-systemd.sh
	$(CUR_DIR)/scripts/install-systemd.sh

uninstall-systemd:
	chmod +x $(CUR_DIR)/scripts/uninstall-systemd.sh
	$(CUR_DIR)/scripts/uninstall-systemd.sh

sys-template:
	-mkdir -p /usr/local/etc/xray /usr/local/etc/hysteria /usr/local/etc/sing-box
	-mkdir -p /etc/nginx/conf.d
	cp server/xray/config/config.json /usr/local/etc/xray/config.json
	cp server/hy2/config/config.toml /usr/local/etc/hysteria/config.toml
	cp server/sing-box/config/config.json /usr/local/etc/sing-box/config.json
	cp server/nginx/conf/acme.conf /etc/nginx/conf.d/acme.conf
	nginx -t || true

start:
	systemctl start nginx xray hy2 sing-box || true

stop:
	systemctl stop nginx xray hy2 sing-box || true

restart:
	systemctl restart nginx xray hy2 sing-box || true

status:
	@systemctl status nginx --no-pager || true
	@systemctl status xray --no-pager || true
	@systemctl status hy2 --no-pager || true
	@systemctl status sing-box --no-pager || true

start-nginx:
	systemctl start nginx

stop-nginx:
	systemctl stop nginx

restart-nginx:
	systemctl restart nginx

start-xray:
	systemctl start xray

stop-xray:
	systemctl stop xray

restart-xray:
	systemctl restart xray

start-hy2:
	systemctl start hy2

stop-hy2:
	systemctl stop hy2

restart-hy2:
	systemctl restart hy2

start-singbox:
	systemctl start sing-box

stop-singbox:
	systemctl stop sing-box

restart-singbox:
	systemctl restart sing-box