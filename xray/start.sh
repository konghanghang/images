#!/bin/bash
xray_reality=1
xray_vision=2
xray_vmess=3
media_enable=1
read -p "请选择模式 1:reality  2:vision 3:vmess: " XRAY_MODEL
export XRAY_MODEL=${XRAY_MODEL:-1}
if [ $XRAY_MODEL -eq $xray_vision ] 
then
    read -p "请输入SSL证书的域名: " XRAY_SSL_HOST
    export XRAY_SSL_HOST=$XRAY_SSL_HOST
fi
read -p "是否开启流媒体转发[0：不开启，1：开启，默认0]: " XRAY_MEDIA
XRAY_MEDIA=${XRAY_MEDIA:-0}

if [ $XRAY_MEDIA -eq $media_enable ]
then
    echo "流媒体转发：开启"
    export XRAY_MEDIA_TAG='netflix-disney'
else
    echo "流媒体转发：关闭"
    export XRAY_MEDIA_TAG='common'
fi

# 生成config.json文件
if [ $XRAY_MODEL -eq $xray_reality ]
then
    echo "reality开启"
    envsubst < conf/config.json.template.reality > conf/config.json
elif [ $XRAY_MODEL -eq $xray_vision ] 
then
    echo "vision开启"
    envsubst < conf/config.json.template.vision > conf/config.json
else
    echo "vmess开启"
    envsubst < conf/config.json.template > conf/config.json
fi

# 取消export设置
unset -v XRAY_MODEL
unset -v XRAY_SSL_HOST
unset -v XRAY_MEDIA_TAG