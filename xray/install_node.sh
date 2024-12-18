#!/bin/bash

# shellcheck disable=SC2034
ADDR=$(curl -s http://104.19.19.19/cdn-cgi/trace|grep loc|cut -d '=' -f 2)

# ==================== 解析命令行参数 ====================
for ARG in "$@"; do
    case $ARG in
        DOMAIN=*)
            DOMAIN="${ARG#*=}"
            shift
            ;;
        CF_API_TOKEN=*)
            CF_API_TOKEN="${ARG#*=}"
            shift
            ;;
        NETFLIX520DNS=*)
            NETFLIX520DNS="${ARG#*=}"
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
if [ -z "$DOMAIN" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$NETFLIX520DNS" ] || [ -z "$PASSWORD" ]; then
    echo "❌ 参数缺失，请传递以下参数："
    echo "  bash $0 DOMAIN=<域名> CF_API_TOKEN=<Cloudflare_API_Token> Netflix520DNS=<NETFLIX520DNS> 节点密码=<PASSWORD>"
    exit 1
fi

apt update
apt install -y curl jq

function caddy_install (){
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install caddy
    caddy add-package github.com/caddy-dns/cloudflare
}

function xray_install (){
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
    wget -q -N --no-check-certificate -O /usr/local/lib/xray/geosite.dat https://github.com/aipeach/v2ray-rules-dat/releases/latest/download/geosite.dat
    wget -q -N --no-check-certificate -O /usr/local/lib/xray/geoip.dat https://github.com/aipeach/v2ray-rules-dat/releases/latest/download/geoip.dat
}

function caddy_config () {
cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    root * /usr/share/caddy
    file_server
    log {
            output discard
    }
    tls {
            dns cloudflare $CF_API_TOKEN
            curves x25519
            protocols tls1.2 tls1.3
    }
    @mywebsocket {
            path /ws
            header Connection *Upgrade*
            header Upgrade websocket
    }
    reverse_proxy @mywebsocket unix//dev/shm/Xray-Trojan-Ws.socket {
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {header.X-Forwarded-For}
    }
}
EOF
}

function xray_config() {
cat > /usr/local/etc/xray/trojan.json <<EOF
{"log":{"loglevel":"warning"},"dns":{"servers":["https+local://one.one.one.one/dns-query","https+local://dns.google/dns-query",{"address":"twdns01.netflix520.com","domains":["full:openai.com","full:chatgpt.com"],"queryStrategy":"UseIPv4"},{"address":"$NETFLIX520DNS","domains":["geosite:netflix520"],"queryStrategy":"UseIPv4"}]},"inbounds":[{"listen":"/dev/shm/Xray-Trojan-Ws.socket,0666","protocol":"trojan","settings":{"clients":[{"password":"$PASSWORD"}]},"streamSettings":{"network":"ws","wsSettings":{"path":"/ws"}}}],"outbounds":[{"protocol":"freedom","settings":{"domainStrategy":"UseIP"}}]}
EOF
# shellcheck disable=SC2002
cat /usr/local/etc/xray/trojan.json | jq '.' > tempxray.json && mv tempxray.json /usr/local/etc/xray/trojan.json
}

function main (){
    # 安装Caddy
    caddy_install
    # 安装Xray
    xray_install
    # 写入Caddy配置
    caddy_config
    # 写入Xray配置
    xray_config
    # 重启 Caddy
    systemctl restart caddy
    # 重启 Xray
    systemctl restart xray@trojan
}

main

LOCAL_IP=$(curl ipv4.ip.sb)

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
