#!/bin/bash
set -euo pipefail

# 一键申请 SSL 证书脚本，基于 acme.sh 和 Cloudflare DNS API
# Version: 2.4

# ==================== 解析命令行参数 ====================
DOMAINS=""
CF_API_TOKEN=""
RELOAD_CMD=""

for ARG in "$@"; do
    case $ARG in
        DOMAINS=*) DOMAINS="${ARG#*=}" ;;
        CF_API_TOKEN=*) CF_API_TOKEN="${ARG#*=}" ;;
        RELOAD_CMD=*) RELOAD_CMD="${ARG#*=}" ;;
        *)
            echo "❌ 未知参数: $ARG"
            echo "用法: bash $0 DOMAINS=example.com[,*.example.com,...] CF_API_TOKEN=xxx [RELOAD_CMD='systemctl reload nginx']"
            exit 1
            ;;
    esac
done

# ==================== 参数校验 ====================
if [[ -z "$DOMAINS" || -z "$CF_API_TOKEN" ]]; then
    echo "❌ 参数缺失，必须提供 DOMAINS 和 CF_API_TOKEN"
    exit 1
fi

# ==================== 自动判断是否是单域名并添加泛域名 ====================
IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"

if [[ ${#DOMAIN_ARRAY[@]} -eq 1 ]]; then
    BASE_DOMAIN="${DOMAIN_ARRAY[0]}"
    echo "🔍 检测到只传入一个域名，自动添加泛域名: *.$BASE_DOMAIN"
    DOMAIN_ARRAY=("$BASE_DOMAIN" "*.$BASE_DOMAIN")
fi

# 使用第一个域名作为主域名
MAIN_DOMAIN="${DOMAIN_ARRAY[0]}"
CERT_INSTALL_DIR="/etc/ssl/$MAIN_DOMAIN"

echo "📋 申请以下域名的证书:"
for D in "${DOMAIN_ARRAY[@]}"; do
    echo "  - $D"
done

# ==================== 安装 acme.sh ====================
ACME_INSTALL_DIR="$HOME/.acme.sh"

echo "🔍 检查 acme.sh 安装状态..."
if [ ! -f "$ACME_INSTALL_DIR/acme.sh" ]; then
    echo "📥 acme.sh 未安装，开始安装..."
    curl https://get.acme.sh | sh
    [ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc" || true
    export PATH="$ACME_INSTALL_DIR:$PATH"
    echo "✅ acme.sh 安装完成。"
else
    echo "✅ acme.sh 已安装。"
    export PATH="$ACME_INSTALL_DIR:$PATH"
fi

# ==================== 设置默认 CA、申请证书 ====================
echo "🔐 设置默认 CA 为 Let's Encrypt..."
acme.sh --set-default-ca --server letsencrypt

echo "🛠️ 开始申请 SSL 证书..."

ACME_CMD=(acme.sh --issue --dns dns_cf --keylength ec-256 --server letsencrypt)
for D in "${DOMAIN_ARRAY[@]}"; do
    ACME_CMD+=(-d "$D")
done

CF_Token="$CF_API_TOKEN" "${ACME_CMD[@]}"

# ==================== 安装证书 ====================
echo "📁 安装证书到: $CERT_INSTALL_DIR"
mkdir -p "$CERT_INSTALL_DIR"

INSTALL_ARGS=(
    --install-cert -d "$MAIN_DOMAIN"
    --ecc
    --key-file "$CERT_INSTALL_DIR/privkey.pem"
    --fullchain-file "$CERT_INSTALL_DIR/fullchain.pem"
)

if [[ -n "${RELOAD_CMD:-}" ]]; then
    INSTALL_ARGS+=(--reloadcmd "$RELOAD_CMD")
    echo "🔄 配置证书续签时执行: $RELOAD_CMD"
else
    echo "ℹ️ 未设置 RELOAD_CMD，证书续签后不会自动重载服务"
fi

CF_Token="$CF_API_TOKEN" acme.sh "${INSTALL_ARGS[@]}"

# ==================== 设置自动续签 ====================
echo "⏳ 设置自动续签任务..."
acme.sh --install-cronjob >/dev/null

# ==================== 检查结果 ====================
if [[ -f "$CERT_INSTALL_DIR/fullchain.pem" && -f "$CERT_INSTALL_DIR/privkey.pem" ]]; then
    echo "✅ 证书申请成功！"
    echo "🔑 私钥路径: $CERT_INSTALL_DIR/privkey.pem"
    echo "📦 全链证书: $CERT_INSTALL_DIR/fullchain.pem"
else
    echo "❌ 证书申请失败，请检查日志。"
    exit 1
fi

echo "🎉 SSL 证书申请流程完成！"