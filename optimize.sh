#!/usr/bin/env bash
echo=echo
for cmd in echo /bin/echo; do
    $cmd >/dev/null 2>&1 || continue

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

OUT_ALERT() {
    echo -e "${CYELLOW}$1${CEND}"
}

OUT_ERROR() {
    echo -e "${CRED}$1${CEND}"
}

OUT_INFO() {
    echo -e "${CCYAN}$1${CEND}"
}

if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -q -E -i "debian|raspbian"; then
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
    OUT_ERROR "[错误] 不支持的操作系统！"
    exit 1
fi

OUT_ALERT "[信息] 更新系统中！"
if [[ ${release} == "centos" ]]; then
    yum makecache
    yum install epel-release -y

    yum update -y
else
    apt update
    apt dist-upgrade -y
    apt autoremove --purge -y
fi

OUT_ALERT "[信息] 优化性能中！"
if [[ ${release} == "centos" ]]; then
    yum install haveged -y
else
    apt install haveged -y
    apt install irqbalance -y
fi

OUT_ALERT "[信息] 优化参数中！"
chattr -i /etc/sysctl.conf
cat > /etc/sysctl.conf << EOF
fs.file-max = 1024000
net.core.default_qdisc = fq
net.core.netdev_max_backlog = 102400
net.core.rmem_default = 65536
net.core.rmem_max = 4194304
net.core.somaxconn = 102400
net.core.wmem_default = 65536
net.core.wmem_max = 4194304
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.ip_default_ttl = 128
net.ipv4.ip_forward = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.neigh.default.gc_interval = 30
net.ipv4.neigh.default.gc_stale_time = 30
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 3
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_time = 10
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_rmem = 4096 65536 4194304
net.ipv4.tcp_sack = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_wmem = 4096 65536 4194304
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
vm.swappiness = 0
EOF
cat > /etc/security/limits.conf << EOF
* soft nofile 102400
* hard nofile 102400
* soft nproc 102400
* hard nproc 102400
root soft nofile 102400
root hard nofile 102400
root soft nproc 102400
root hard nproc 102400
EOF
cat > /etc/systemd/journald.conf <<EOF
[Journal]
SystemMaxUse=384M
SystemMaxFileSize=128M
ForwardToSyslog=no
EOF
sysctl -p

OUT_INFO "[信息] 优化完毕！"
exit 0
