#!/bin/sh
echo=echo
for cmd in echo /bin/echo; do
    $cmd > /dev/null 2>&1 || continue

    if ! $cmd -e "" | grep -qE '^-e'; then
        echo=$cmd
        break
    fi
done

CSI=$($echo -e "\033[")
CEND="${CSI}0m"
CDGREEN="${CSI}32m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"
CMAGENTA="${CSI}1;35m"
CCYAN="${CSI}1;36m"
CSUCCESS="$CDGREEN"
CFAILURE="$CRED"
CQUESTION="$CMAGENTA"
CWARNING="$CYELLOW"
CMSG="$CCYAN"

PLATFORM=$1
if [ -z "$PLATFORM" ]; then
    ARCH="amd64"
else
    case "$PLATFORM" in
        linux/386)
            ARCH="386"
            ;;
        linux/amd64)
            ARCH="amd64"
            ;;
        linux/arm/v6)
            ARCH="arm6"
            ;;
        linux/arm/v7)
            ARCH="arm7"
            ;;
        linux/arm64|linux/arm64/v8)
            ARCH="arm64"
            ;;
        linux/ppc64le)
            ARCH="ppc64le"
            ;;
        linux/s390x)
            ARCH="s390x"
            ;;
        *)
            ARCH=""
            ;;
    esac
fi
[ -z "${ARCH}" ] && echo "${CRED}[错误] 不支持的操作系统！${CEND}" && exit 1

CADDY_FILE="caddy_linux_${ARCH}"

rm -f /usr/local/bin/caddy
rm -f /etc/caddy/Caddyfile
rm -f /etc/systemd/system/caddy.service
rm -rf /etc/caddy
rm -rf /etc/ssl/caddy
rm -rf /var/log/caddy
rm -rf /var/www/default

echo "${CYELLOW}正在下载二进制文件: ${CADDY_FILE}${CEND}"
wget -O /usr/local/bin/caddy https://dl.lamp.sh/files/${CADDY_FILE} > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "${CRED}Error: 无法下载二进制文件: ${CADDY_FILE}${CEND}" && exit 1
fi

chmod +x /usr/local/bin/caddy

wget -O /etc/systemd/system/caddy.service https://raw.githubusercontent.com/aipeach/shell/master/service/caddy.service > /dev/null 2>&1

chmod 644 /etc/systemd/system/caddy.service

mkdir /etc/caddy
mkdir /etc/ssl/caddy
mkdir /var/log/caddy
mkdir -p /var/www/default

echo ":80" > /etc/caddy/Caddyfile
echo "{" >> /etc/caddy/Caddyfile
echo "  root /var/www/default" >> /etc/caddy/Caddyfile
echo "  log /var/log/caddy/access.log {" >> /etc/caddy/Caddyfile
echo "  rotate_size 50" >> /etc/caddy/Caddyfile
echo "  rotate_keep 10" >> /etc/caddy/Caddyfile
echo "  except /video" >> /etc/caddy/Caddyfile
echo "  }" >> /etc/caddy/Caddyfile
echo "  proxy /video 127.0.0.1:10000 {" >> /etc/caddy/Caddyfile
echo "    websocket" >> /etc/caddy/Caddyfile
echo "    header_upstream -Origin" >> /etc/caddy/Caddyfile
echo "  }" >> /etc/caddy/Caddyfile
echo "  gzip" >> /etc/caddy/Caddyfile
echo "}" >> /etc/caddy/Caddyfile

chown -R root:www-data /var/www
chown -R root:www-data /etc/caddy
chmod 0770 /etc/ssl/caddy
chown -R www-data:www-data /var/www
chown -R www-data:www-data /etc/ssl/caddy
chown -R www-data:www-data /var/log/caddy

systemctl daemon-reload
systemctl restart caddy

echo "${CYELLOW}Caddy已安装完成${CEND}"
echo "${CYELLOW}配置文件: /etc/caddy/Caddyfile${CEND}"
echo "${CYELLOW}查看日志: tail /var/log/caddy/access.log${CEND}"
echo "${CYELLOW}Caddy 使用命令:${CEND}"
echo "${CYELLOW}启动Caddy: systemctl start caddy${CEND}"
echo "${CYELLOW}停止Caddy: systemctl stop caddy${CEND}"
echo "${CYELLOW}重启Caddy: systemctl restart caddy${CEND}"
echo "${CYELLOW}查看状态: systemctl status caddy${CEND}"
echo "${CYELLOW}开机自启: systemctl enable caddy${CEND}"
echo "${CYELLOW}开机禁用: systemctl disable caddy${CEND}"
