#!/bin/bash

# 配置参数
DOMAIN_FILE_URL="https://example.com/domains.txt" # 替换为域名列表文件的实际URL
DOMAIN_FILE="domains.txt"
OUTPUT_FILE="dns_check_results.txt"

TELEGRAM_BOT_TOKEN="your_bot_token" # 替换为你的Telegram Bot Token
TELEGRAM_CHAT_ID="your_chat_id"     # 替换为你的Telegram Chat ID
SOCKS5_PROXY="127.0.0.1:1080"       # 替换为你的 SOCKS5 代理地址
CHINA_DNS_SERVER="119.29.29.29"     # 替换为中国 DNS 服务器
AMESSAGE="ABCDEFG"                  # 自定义消息

# 下载域名列表
echo "⬇️ Downloading domain list using SOCKS5 proxy..."
curl -s --socks5-hostname "$SOCKS5_PROXY" -o "$DOMAIN_FILE" "$DOMAIN_FILE_URL"

# 检查文件是否成功下载
if [ -f "$DOMAIN_FILE" ] && [ -s "$DOMAIN_FILE" ]; then
    echo "✅ Domain list downloaded and saved successfully!"
    
    # 发送 Telegram 消息
    telegram_message="域名列表下载并保存成功。"
    telegram_api="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    curl -s --socks5-hostname "$SOCKS5_PROXY" -X POST "$telegram_api" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$telegram_message" \
        -d parse_mode="Markdown" &>/dev/null
else
    echo "❌ Failed to download domain file!"
    exit 1
fi

# 清空输出文件
> "$OUTPUT_FILE"

# Cloudflare DoH API 查询函数
function query_cloudflare() {
    curl -s --socks5-hostname "$SOCKS5_PROXY" "https://cloudflare-dns.com/dns-query?name=$1&type=A" -H "accept: application/dns-json" |
        jq -r '.Answer[]?.data' 2>/dev/null | sort
}

# dig 查询函数（无代理），过滤非 IP 地址
function query_dig() {
    dig +short "$1" @$CHINA_DNS_SERVER 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort
}

# 初始化结果统计
no_dns_records=()  # 无 DNS 记录的域名
mismatched_domains=()  # DNS 记录不匹配的域名

# 处理每个域名
while IFS= read -r DOMAIN; do
    if [[ -z "$DOMAIN" ]]; then
        continue # 跳过空行
    fi

    # 查询记录
    cloudflare_records=$(query_cloudflare "$DOMAIN")
    dig_records=$(query_dig "$DOMAIN")

    # 输出当前域名结果
    echo "Domain: $DOMAIN" >> "$OUTPUT_FILE"

    # 判断无 DNS 记录的情况
    if [[ -z "$cloudflare_records" && -z "$dig_records" ]]; then
        echo "❌ No DNS records found for $DOMAIN!" >> "$OUTPUT_FILE"
        echo "---------------------------------" >> "$OUTPUT_FILE"
        no_dns_records+=("$DOMAIN")
        continue
    fi

    echo "Cloudflare DoH Records:" >> "$OUTPUT_FILE"
    echo "$cloudflare_records" >> "$OUTPUT_FILE"
    echo "DIG Records:" >> "$OUTPUT_FILE"
    echo "$dig_records" >> "$OUTPUT_FILE"

    # 比较结果
    if [ "$cloudflare_records" == "$dig_records" ]; then
        echo "✅ The DNS records match!" >> "$OUTPUT_FILE"
    else
        echo "❌ DNS records do not match for $DOMAIN!" >> "$OUTPUT_FILE"
        mismatched_domains+=("$DOMAIN")
    fi
    echo "---------------------------------" >> "$OUTPUT_FILE"
done < "$DOMAIN_FILE"

# 构建 Telegram 消息内容
if [[ ${#no_dns_records[@]} -eq 0 && ${#mismatched_domains[@]} -eq 0 ]]; then
    telegram_message="检查完毕，没有域名被墙"
else
    telegram_message="检查结果:\n\n"
    if [[ ${#no_dns_records[@]} -gt 0 ]]; then
        telegram_message+="以下域名没有设置 DNS 记录:\n"
        for domain in "${no_dns_records[@]}"; do
            telegram_message+="Domain: $domain 该域名dns记录未配置\n"
        done
    fi
    if [[ ${#mismatched_domains[@]} -gt 0 ]]; then
        telegram_message+="\n以下域名 DNS 记录不匹配（可能被墙）:\n"
        for domain in "${mismatched_domains[@]}"; do
            telegram_message+="Domain: $domain 该域名被墙\n"
        done
    fi
    telegram_message+="\n$AMESSAGE"
fi

# 使用 printf 格式化消息，确保换行符正确解析
formatted_message=$(printf "$telegram_message")

# 发送 Telegram 通知
echo "📤 Sending Telegram notification using SOCKS5 proxy..."
telegram_api="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
curl -s --socks5-hostname "$SOCKS5_PROXY" -X POST "$telegram_api" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$formatted_message" \
    -d parse_mode="Markdown" &>/dev/null

echo "✅ DNS check completed and notification sent!"
