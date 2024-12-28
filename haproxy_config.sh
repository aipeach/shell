#!/bin/bash

# 检查输入参数
if [ $# -ne 3 ]; then
  echo "Usage: $0 <start_port-end_port> <ip_address> <output_file>"
  exit 1
fi

# 解析参数
PORT_RANGE=$1
IP_ADDRESS=$2
OUTPUT_FILE=$3

# 提取起始端口和结束端口
START_PORT=$(echo $PORT_RANGE | cut -d'-' -f1)
END_PORT=$(echo $PORT_RANGE | cut -d'-' -f2)

# 校验端口范围是否合法
if ! [[ $START_PORT =~ ^[0-9]+$ && $END_PORT =~ ^[0-9]+$ && $START_PORT -le $END_PORT ]]; then
  echo "Invalid port range: $PORT_RANGE"
  exit 1
fi

# 开始生成配置
> $OUTPUT_FILE  # 清空或创建输出文件
for ((PORT=$START_PORT; PORT<=$END_PORT; PORT++)); do
  cat <<EOF >> $OUTPUT_FILE
frontend frontend_$PORT
  bind 0.0.0.0:$PORT
  mode tcp
  default_backend backend_$PORT
backend backend_$PORT
  mode tcp
  server server$PORT $IP_ADDRESS:$PORT send-proxy

EOF
done

echo "Configuration file generated: $OUTPUT_FILE"
