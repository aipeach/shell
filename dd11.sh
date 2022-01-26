#! /bin/bash

apt-get update
apt-get install curl -y
curl -fLO https://raw.githubusercontent.com/bohanyang/debi/master/debi.sh && chmod a+rx debi.sh
bash debi.sh --cdn --network-console --ethx --bbr --user root --password Abc123 --authorized-keys-url https://github.com/aipeach.keys --timezone Asia/Shanghai
shutdown -r now
