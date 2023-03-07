#!/bin/bash

read -p "请输入http端口号[80]: " NAVIE_HTTP_PORT
export NAVIE_HTTP_PORT=${NAVIE_HTTP_PORT:-80}
read -p "请输入https端口号[443]: " NAVIE_HTTPS_PORT
export NAVIE_HTTPS_PORT=${NAVIE_HTTPS_PORT:-443}
read -p "请输入邮箱: " NAVIE_SSL_MAIL
export NAVIE_SSL_MAIL=$NAVIE_SSL_MAIL
read -p "请输入用户申请证书的域名: " NAVIE_SSL_HOST
export NAVIE_SSL_HOST=$NAVIE_SSL_HOST
read -p "请输入默认代理到的网站域名: " NAVIE_PROXY_HOST
export NAVIE_PROXY_HOST=$NAVIE_PROXY_HOST

echo "输入的http端口号： $NAVIE_HTTP_PORT, https端口号： $NAVIE_HTTPS_PORT, 邮箱：$NAVIE_SSL_MAIL, 申请证书的域名: $NAVIE_SSL_HOST, 代理到的网站域名: $NAVIE_PROXY_HOST"

# 生成Caddyfile
envsubst < conf/Caddyfile.template > conf/Caddyfile
# 生成docker-compose.yaml文件
envsubst < ./docker-compose.yaml.template > ./docker-compose.yaml

# 取消export设置
unset -v NAVIE_HTTP_PORT
unset -v NAVIE_HTTPS_PORT
unset -v NAVIE_SSL_MAIL
unset -v NAVIE_SSL_HOST
unset -v NAVIE_PROXY_HOST