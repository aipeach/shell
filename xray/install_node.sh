#!/bin/bash

# ==================== 解析命令行参数 ====================
for ARG in "$@"; do
    case $ARG in
        DOMAIN=*)
            DOMAIN="${ARG#*=}"
            shift
            ;;
        EMAIL=*)
            EMAIL="${ARG#*=}"
            shift
            ;;
        CF_API_TOKEN=*)
            CF_API_TOKEN="${ARG#*=}"
            shift
            ;;
        XRAY_PORT=*)
            XRAY_PORT="${ARG#*=}"
            shift
            ;;
        PASSWORD=*)
            PASSWORD="${ARG#*=}"
            shift
            ;;
        *)
            echo "未知参数: $ARG"
            exit 1
            ;;
    esac
done

# ==================== 参数校验 ====================
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$XRAY_PORT" ] || [ -z "$PASSWORD" ]; then
    echo "❌ 参数缺失，请传递以下参数："
    echo "  bash $0 DOMAIN=<域名> EMAIL=<邮箱> CF_API_TOKEN=<Cloudflare_API_Token> 节点端口=<XRAY_PORT> 节点密码=<PASSWORD>"
    exit 1
fi

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

function xray_config() {
cat > /usr/local/etc/xray/trojan.json <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"port":$XRAY_PORT,"protocol":"trojan","settings":{"clients":[{"password":"$PASSWORD"}]},"streamSettings":{"network":"ws","security":"tls","wsSettings":{"path":"/ws"},"tlsSettings":{"alpn":["h2","http/1.1"],"certificates":[{"certificateFile":"/etc/ssl/$DOMAIN/fullchain.pem","keyFile":"/etc/ssl/$DOMAIN/privkey.pem"}]}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
}

bash <(curl -L -s https://raw.githubusercontent.com/aipeach/shell/refs/heads/master/acme_ssl_request.sh) \
CF_API_TOKEN="$CF_API_TOKEN" \
EMAIL="$EMAIL" \
DOMAIN="$DOMAIN" \
RELOAD_CMD="systemctl restart xray@trojan"

xray_config

LOCAL_IP=$(curl ipv4.ip.sb)

systemctl restart xray@trojan

echo -e "✅ Clash节点信息"
echo -e "----------------------------------------------------"
echo -e "proxies:"
echo -e "    - name: Trojan-Test"
echo -e "      type: trojan"
echo -e "      server: $LOCAL_IP"
echo -e "      port: $XRAY_PORT"
echo -e "      password: $PASSWORD"
echo -e "      udp: true"
echo -e "      sni: $DOMAIN"
echo -e "      network: ws"
echo -e "      ws-opts:"
echo -e "        path: /ws"
echo -e "----------------------------------------------------"
