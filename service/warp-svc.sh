#!/bin/bash
cat > /lib/systemd/system/warp-svc.service <<EOF
[Unit]
Description=Cloudflare Warp Client
After=pre-network.target

[Service]
Type=simple
ExecStart=/bin/warp-svc
DynamicUser=no
CapabilityBoundingSet=CAP_NET_ADMIN
AmbientCapabilities=CAP_NET_ADMIN
StateDirectory=cloudflare-warp
RuntimeDirectory=cloudflare-warp
LogsDirectory=cloudflare-warp
Restart=always
RestartSec=5
StartLimitInterval=100s
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
nohup systemctl restart warp-svc > /dev/null 2>&1 &
