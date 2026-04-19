#!/usr/bin/env bash
set -euo pipefail

# ========= 参数 =========
DOMAIN=""
PORT=""
CF_TOKEN=""

usage() {
  echo "用法："
  echo "  bash install-caddy-static.sh --domain example.com --port 8443 --cf-token xxx"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="$2"; shift 2 ;;
    --port)
      PORT="$2"; shift 2 ;;
    --cf-token)
      CF_TOKEN="$2"; shift 2 ;;
    *)
      usage ;;
  esac
done

[[ -z "$DOMAIN" || -z "$PORT" || -z "$CF_TOKEN" ]] && usage

if [[ $EUID -ne 0 ]]; then
  echo "请用 root 运行"
  exit 1
fi

echo "========== 开始部署 =========="

# ========= 1. 安装 Caddy =========
echo "[1/6] 安装 Caddy..."

apt update
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null

chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
chmod o+r /etc/apt/sources.list.d/caddy-stable.list

apt update
apt install -y caddy

# ========= 2. 安装 Cloudflare 插件 =========
echo "[2/6] 检查 Cloudflare DNS 插件..."

if caddy list-modules | grep -q '^dns.providers.cloudflare$'; then
  echo "已存在插件"
else
  echo "安装插件..."
  caddy add-package github.com/caddy-dns/cloudflare
fi

# ========= 3. 写环境变量 =========
echo "[3/6] 写入 Cloudflare Token..."

mkdir -p /etc/caddy
cat > /etc/caddy/caddy.env <<EOF
CLOUDFLARE_API_TOKEN=${CF_TOKEN}
EOF

chmod 600 /etc/caddy/caddy.env

# ========= 4. 写 Caddyfile =========
echo "[4/6] 生成 Caddyfile..."

cat > /etc/caddy/Caddyfile <<EOF
{
    acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
}

${DOMAIN}:${PORT} {
    tls {
        key_type p256
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    root * /usr/share/caddy
    file_server

    encode gzip zstd
}
EOF

# ========= 5. systemd =========
echo "[5/6] 配置 systemd..."

mkdir -p /etc/systemd/system/caddy.service.d

cat > /etc/systemd/system/caddy.service.d/override.conf <<EOF
[Service]
EnvironmentFile=/etc/caddy/caddy.env
ExecReload=
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
EOF

systemctl daemon-reload

# ========= 6. 启动 =========
echo "[6/6] 启动服务..."

export CLOUDFLARE_API_TOKEN="$CF_TOKEN"
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

systemctl enable --now caddy
systemctl restart caddy

# ========= 完成 =========
echo
echo "✅ 部署完成"
echo "----------------------------------"
echo "域名:    https://${DOMAIN}:${PORT}"
echo "目录:    /usr/share/caddy"
echo
echo "测试页面："
echo "  echo 'hello world' > /usr/share/caddy/index.html"
echo
echo "查看状态："
echo "  systemctl status caddy"
echo
echo "查看日志："
echo "  journalctl -u caddy -f"
echo
echo "重载配置："
echo "  systemctl reload caddy"
echo "----------------------------------"
