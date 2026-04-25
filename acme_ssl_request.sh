#!/bin/bash
set -euo pipefail

# 一键申请 SSL 证书脚本，基于 acme.sh 和 Cloudflare DNS API
# Version: 2.6

# ==================== 解析命令行参数 ====================
DOMAINS=""
CF_API_TOKEN=""
RELOAD_CMD=""
LIST_RENEW="0"
SHOW_HELP="0"

print_help() {
    cat <<'EOF'
用法:
  bash acme_ssl_request.sh DOMAINS=example.com[,*.example.com,...] CF_API_TOKEN=xxx [RELOAD_CMD='systemctl reload nginx']
  bash acme_ssl_request.sh LIST_RENEW=1
  bash acme_ssl_request.sh help

参数说明:
  DOMAINS       证书域名列表，逗号分隔；若只传一个域名会自动补充泛域名
  CF_API_TOKEN  Cloudflare API Token（按主域名隔离保存，不会互相覆盖）
  RELOAD_CMD    续签后执行的重载命令（可选）
  LIST_RENEW=1  查看由本脚本创建的续签任务（只查询不申请）
  help|-h|--help 显示帮助信息
EOF
}

for ARG in "$@"; do
    case $ARG in
        help|-h|--help) SHOW_HELP="1" ;;
        DOMAINS=*) DOMAINS="${ARG#*=}" ;;
        CF_API_TOKEN=*) CF_API_TOKEN="${ARG#*=}" ;;
        RELOAD_CMD=*) RELOAD_CMD="${ARG#*=}" ;;
        LIST_RENEW=*) LIST_RENEW="${ARG#*=}" ;;
        *)
            echo "❌ 未知参数: $ARG"
            print_help
            exit 1
            ;;
    esac
done

# ==================== 帮助信息 ====================
if [[ "$SHOW_HELP" == "1" ]]; then
    print_help
    exit 0
fi

# ==================== 仅查看续签任务 ====================
if [[ "$LIST_RENEW" == "1" ]]; then
    echo "📋 当前由本脚本创建的续签任务（acme-renew）:"
    CURRENT_CRON="$(crontab -l 2>/dev/null || true)"
    MATCHED="$(printf "%s\n" "$CURRENT_CRON" | grep 'acme-renew:' || true)"

    if [[ -z "$MATCHED" ]]; then
        echo "ℹ️ 未找到续签任务"
        exit 0
    fi

    printf "%s\n" "$MATCHED"
    exit 0
fi

# ==================== 参数校验 ====================
if [[ -z "$DOMAINS" || -z "$CF_API_TOKEN" ]]; then
    echo "❌ 参数缺失，必须提供 DOMAINS 和 CF_API_TOKEN"
    print_help
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

# 为每个主域名隔离 acme 配置，避免不同域名之间覆盖 CF_Token
ACME_CONFIG_ROOT="$HOME/.acme.sh-configs"
ACME_CONFIG_HOME="$ACME_CONFIG_ROOT/$MAIN_DOMAIN"

mkdir -p "$ACME_CONFIG_HOME"

echo "📋 申请以下域名的证书:"
for D in "${DOMAIN_ARRAY[@]}"; do
    echo "  - $D"
done

# ==================== 安装 acme.sh ====================
ACME_INSTALL_DIR="$HOME/.acme.sh"
ACME_BIN="$ACME_INSTALL_DIR/acme.sh"

echo "🔍 检查 acme.sh 安装状态..."
if [ ! -f "$ACME_BIN" ]; then
    echo "📥 acme.sh 未安装，开始安装..."
    curl https://get.acme.sh | sh
    [ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc" || true
    export PATH="$ACME_INSTALL_DIR:$PATH"
    echo "✅ acme.sh 安装完成。"
else
    echo "✅ acme.sh 已安装。"
    export PATH="$ACME_INSTALL_DIR:$PATH"
fi

ACME_SH=("$ACME_BIN" --home "$ACME_CONFIG_HOME" --config-home "$ACME_CONFIG_HOME")

# ==================== 设置默认 CA、申请证书 ====================
echo "🔐 设置默认 CA 为 Let's Encrypt..."
"${ACME_SH[@]}" --set-default-ca --server letsencrypt

echo "🛠️ 开始申请 SSL 证书..."

ACME_CMD=("${ACME_SH[@]}" --issue --dns dns_cf --keylength ec-256 --server letsencrypt)
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

CF_Token="$CF_API_TOKEN" "${ACME_SH[@]}" "${INSTALL_ARGS[@]}"

# ==================== 设置自动续签 ====================
echo "⏳ 设置自动续签任务..."
CRON_TAG="# acme-renew:$MAIN_DOMAIN"
CRON_JOB="17 3 * * * $ACME_BIN --cron --home $ACME_CONFIG_HOME --config-home $ACME_CONFIG_HOME >/dev/null 2>&1 $CRON_TAG"
CURRENT_CRON="$(crontab -l 2>/dev/null || true)"

if grep -Fq "$CRON_TAG" <<< "$CURRENT_CRON"; then
    echo "✅ 已存在该域名的续签任务，跳过添加"
else
    {
        printf "%s\n" "$CURRENT_CRON"
        printf "%s\n" "$CRON_JOB"
    } | crontab -
    echo "✅ 已添加域名独立续签任务"
fi

# ==================== 检查结果 ====================
if [[ -f "$CERT_INSTALL_DIR/fullchain.pem" && -f "$CERT_INSTALL_DIR/privkey.pem" ]]; then
    echo "✅ 证书申请成功！"
    echo "🔑 私钥路径: $CERT_INSTALL_DIR/privkey.pem"
    echo "📦 全链证书: $CERT_INSTALL_DIR/fullchain.pem"
    echo "🗂️ acme 配置目录: $ACME_CONFIG_HOME"
else
    echo "❌ 证书申请失败，请检查日志。"
    exit 1
fi

echo "🎉 SSL 证书申请流程完成！"
