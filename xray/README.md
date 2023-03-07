# xray配置
run命令：
```shell
docker run -d \
    --name xray \
    --privileged \
    -v /home/ubuntu/env/xray/config.json:/etc/xray/config.json \
    -v /home/ubuntu/env/xray/logs:/var/log/xray \
    -v /etc/letsencrypt/:/etc/letsencrypt/ \
    -p 443:443 \
    --network mynet \
    --restart unless-stopped \
    teddysun/xray:1.7.2
```

使用naiveproxy申请的证书，需要修改xray的config文件中的域名。