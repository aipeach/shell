#!/bin/bash

# 一键申请 SSL 证书脚本，基于 acme.sh 和 Cloudflare DNS API
# 支持通过命令行传递参数运行
# Version: 2.2

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
        RELOAD_CMD=*)
            RELOAD_CMD="${ARG#*=}"
            shift
            ;;
        *)
            echo "未知参数: $ARG"
            exit 1
            ;;
    esac
done

# ==================== 参数校验 ====================
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$RELOAD_CMD" ]; then
    echo "❌ 参数缺失，请传递以下参数："
    echo "  bash $0 DOMAIN=<域名> EMAIL=<邮箱> CF_API_TOKEN=<Cloudflare_API_Token> RELOAD_CMD=<重启命令>"
    exit 1
fi

# ==================== 配置区域 ====================
ACME_INSTALL_DIR="$HOME/.acme.sh"         # acme.sh 安装目录
CERT_INSTALL_DIR="/etc/ssl/$DOMAIN"       # 证书安装目录

# ==================== 工具检查与安装 ====================
echo "检查是否已安装 acme.sh..."
if [ ! -f "$ACME_INSTALL_DIR/acme.sh" ]; then
    echo "acme.sh 未安装，正在安装..."
    curl https://get.acme.sh | sh
    export PATH=$HOME/.acme.sh:$PATH
    echo "acme.sh 安装完成！"
else
    echo "acme.sh 已安装。"
fi

# 添加 acme.sh 到环境变量
export PATH=$HOME/.acme.sh:$PATH

# ==================== 申请 SSL 证书 ====================
echo "开始申请 SSL 证书 (基于 Cloudflare DNS API)..."

# 设置 Cloudflare API Token
export CF_Token="$CF_API_TOKEN"

# 执行 acme.sh 命令申请证书
acme.sh --issue --dns dns_cf -d "$DOMAIN" --keylength ec-384 --email "$EMAIL"

# ==================== 安装证书到指定路径 ====================
mkdir -p "$CERT_INSTALL_DIR"

echo "安装证书到目录: $CERT_INSTALL_DIR"
acme.sh --install-cert -d "$DOMAIN" \
    --ecc \
    --key-file "$CERT_INSTALL_DIR/privkey.pem" \
    --fullchain-file "$CERT_INSTALL_DIR/fullchain.pem" \
    --reloadcmd "$RELOAD_CMD"

# ==================== 自动续签任务设置 ====================
echo "设置自动续签任务..."
acme.sh --install-cronjob > /dev/null

# ==================== 结果检查 ====================
if [ -f "$CERT_INSTALL_DIR/fullchain.pem" ] && [ -f "$CERT_INSTALL_DIR/privkey.pem" ]; then
    echo "✅ SSL 证书申请成功！"
    echo "证书路径："
    echo "  - 私钥文件: $CERT_INSTALL_DIR/privkey.pem"
    echo "  - 全链证书: $CERT_INSTALL_DIR/fullchain.pem"
    echo "证书续签后将自动执行命令: $RELOAD_CMD"
else
    echo "❌ SSL 证书申请失败，请检查日志。"
    exit 1
fi

echo "脚本执行完成！🎉"
