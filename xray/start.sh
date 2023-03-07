#!/bin/bash

read -p "请输入SSL证书的域名: " XRAY_SSL_HOST
export XRAY_SSL_HOST=$XRAY_SSL_HOST
read -p "是否开启流媒体转发[0：不开启，1：开启，默认0]: " XRAY_MEDIA
XRAY_MEDIA=${XRAY_MEDIA:-0}
read -p "是否开启vision[0：不开启，1：开启，默认0]: " XRAY_VISION
XRAY_VISION=${XRAY_VISION:-0}

media_enable=1
if [ $XRAY_MEDIA -eq $media_enable ]
then
    echo "流媒体转发：开启"
    export XRAY_MEDIA_TAG='netflix-disney'
else
    echo "流媒体转发：关闭"
    export XRAY_MEDIA_TAG='common'
fi

# 生成config.json文件
vision_enable=1
if [ $XRAY_VISION -eq $vision_enable ]
then
    echo "vision：开启"
    envsubst < conf/config.json.template.vision > conf/config.json
else
    echo "vision：关闭"
    envsubst < conf/config.json.template > conf/config.json
fi

# 取消export设置
unset -v XRAY_SSL_HOST
unset -v XRAY_MEDIA_TAG