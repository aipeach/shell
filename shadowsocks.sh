#!/usr/bin/env bash
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

if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -q -E -i "raspbian|debian"; then
    release="debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -q -E -i "raspbian|debian"; then
    release="debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${CRED}[错误] 不支持的操作系统！${CEND}"
    exit 1
fi

echo -e "${CYELLOW}[信息] 正在更新系统中！${CEND}"
if [[ ${release} == "centos" ]]; then
    yum makecache
    yum install epel-release -y
    yum update -y
else
    apt update
    apt dist-upgrade -y
fi

echo -e "${CYELLOW}[信息] 正在安装依赖中！${CEND}"
if [[ ${release} == "centos" ]]; then
    yum install python3 python3-pip git -y
    yum install net-tools libsodium libffi libffi-devel openssl-devel -y
    systemctl stop firewalld
    systemctl disable firewalld
else
    apt install python3 python3-pip libffi-dev libssl-dev git libsodium-dev -y
fi

echo -e "${CYELLOW}[信息] 创建文件夹中！${CEND}"
rm -rf /opt/shadowsocks
rm -f /etc/systemd/system/shadowsocks@.service
mkdir /opt/shadowsocks

echo -e "${CYELLOW}[信息] 正在安装后端中！${CEND}"
git clone https://github.com/Anankke/shadowsocks /opt/shadowsocks/default
cd /opt/shadowsocks/default
cp /opt/shadowsocks/default/apiconfig.py /opt/shadowsocks/default/userapiconfig.py
cp /opt/shadowsocks/default/config.json /opt/shadowsocks/default/user-config.json
sed -i "s|SPEEDTEST = 6|SPEEDTEST = 0|" /opt/shadowsocks/default/userapiconfig.py
echo -e "1.1.1.1\n8.8.8.8" >> /opt/shadowsocks/default/dns.conf


echo -e "${CYELLOW}[信息] 正在安装依赖中！${CEND}"
pip3 install --upgrade pip setuptools
pip3 install -r /opt/shadowsocks/default/requirements.txt

echo -e "${CYELLOW}[信息] 正在写入服务配置中！${CEND}"
echo "[Unit]" > /etc/systemd/system/shadowsocks@.service
echo "Description=Getluffy ShadowsocksR Server" >> /etc/systemd/system/shadowsocks@.service
echo "After=network.target" >> /etc/systemd/system/shadowsocks@.service
echo "" >> /etc/systemd/system/shadowsocks@.service
echo "[Service]" >> /etc/systemd/system/shadowsocks@.service
echo "Type=simple" >> /etc/systemd/system/shadowsocks@.service
echo "LimitCPU=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitFSIZE=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitDATA=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitSTACK=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitCORE=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitRSS=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitNOFILE=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitAS=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitNPROC=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitMEMLOCK=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitLOCKS=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitSIGPENDING=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitMSGQUEUE=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitRTPRIO=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "LimitRTTIME=infinity" >> /etc/systemd/system/shadowsocks@.service
echo "ExecStart=/usr/bin/python3 /opt/shadowsocks/%i/server.py" >> /etc/systemd/system/shadowsocks@.service
echo "Restart=always" >> /etc/systemd/system/shadowsocks@.service
echo "RestartSec=4" >> /etc/systemd/system/shadowsocks@.service
echo "" >> /etc/systemd/system/shadowsocks@.service
echo "[Install]" >> /etc/systemd/system/shadowsocks@.service
echo "WantedBy=multi-user.target" >> /etc/systemd/system/shadowsocks@.service
systemctl daemon-reload

echo -e "${CYELLOW}[信息] 安装完毕！${CEND}"
echo -e "${CYELLOW}[信息] 重复安装会删除原有配置！${CEND}"
exit 0
