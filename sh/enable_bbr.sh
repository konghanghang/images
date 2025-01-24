#!/bin/bash

# 检查系统是否为 Debian 或 Ubuntu
if [[ ! -f /etc/debian_version ]]; then
  echo "此脚本仅支持 Debian 或 Ubuntu 系统，当前系统不支持。"
  exit 1
fi

# 检查是否已经启用了BBR
if lsmod | grep -q 'tcp_bbr'; then
  echo "BBR 已经启用，退出脚本。"
  exit 0
fi

# 开启BBR
echo "启用BBR..."

# 添加BBR配置到 sysctl.conf
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

# 重新加载配置
sysctl -p

# 输出当前可用的拥塞控制算法
sysctl net.ipv4.tcp_available_congestion_control

echo "BBR 配置完成。"