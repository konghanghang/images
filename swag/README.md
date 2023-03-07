# swag安装启动
使用`docker run`命令
```shell
docker run -d \
  --name=swagtest \
  --cap-add=NET_ADMIN \
  --net=mynet \
  -e PUID=1000 \
  -e PGID=1000 \
  -e DOMAIN=www.test.com \
  -e EMAIL=yslao@outlook.com \
  -e CUSTOMIZE_CMD="envsubst '$$DOMAIN' < /config/nginx/default.template > /config/nginx/site-confs/default1" \
  -p 8080:80 \
  -v $PWD/config/nginx/default.template:/config/nginx/default.template \
  -v $PWD/config/nginx/site-confs:/config/nginx/site-confs \
  --restart unless-stopped \
  konghanghang/swag:1.27.1
   -c "envsubst '$${DOMAIN}' < /config/nginx/default.template > /config/nginx/site-confs/default1"
```

## dns校验
run命令
```shell
 docker run -d --name=swag \
  --cap-add=NET_ADMIN \
  --net=mynet \
  -e PUID=1000 \
  -e PGID=1000 \
  -e URL=test.top \
  -e SUBDOMAINS=test \
  -e VALIDATION=dns \
  -e DNSPLUGIN=aliyun \
  -p 80:80 \
  -p 443:443 \
  -v $PWD/config:/config \
  --restart unless-stopped \
  konghanghang/swag:1.27.0
```
## http校验
run命令
```shell
docker run -d \
  --name=swag \
  --cap-add=NET_ADMIN \
  --net=mynet \
  -e PUID=1000 \
  -e PGID=1000 \
  -e URL=test.top \
  -e SUBDOMAINS=test \
  -e VALIDATION=http \
  -e ONLY_SUBDOMAINS=true \
  -e EMAIL=yslao@outlook.com \
  -p 80:80 \
  -p 443:443 \
  -v $PWD/config:/config \
  --restart unless-stopped \
  konghanghang/swag:1.27.0
```