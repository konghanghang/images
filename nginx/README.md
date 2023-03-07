# nginx配置
run命令：
```shell
docker run -d  \
    --name nginx \
    --privileged \
    --restart unless-stopped \
    -m 200m \
    -v $PWD/nginx/nginx.conf:/etc/nginx/nginx.conf \
    -v $PWD/nginx/conf.d:/etc/nginx/conf.d \
    -v $PWD/nginx/html:/usr/share/nginx/html \
    -v $PWD/nginx/logs:/var/log/nginx \
    -p 80:80 \
    -p 443:443 \
    -e HOST=www.baidu.com \
    --entrypoint=/docker-entrypoint.sh && "envsubst '${HOST}' < /etc/nginx/conf.d/default.template > /etc/nginx/conf.d/default.conf"
    --network mynet \
    nginx:1.22.0 -c "envsubst '${HOST}' < /etc/nginx/default.template > /etc/nginx/default.conf"
```

```shell
docker run -d  \
    --name nginx \
    --privileged \
    --restart unless-stopped \
    -m 200m \
    -v $PWD/nginx/nginx.conf:/etc/nginx/nginx.conf \
    -v $PWD/nginx/conf.d:/etc/nginx/conf.d \
    -v $PWD/nginx/default.template:/etc/nginx/default.template \
    -v $PWD/nginx/html:/usr/share/nginx/html \
    -v $PWD/nginx/logs:/var/log/nginx \
    -p 8001:80 \
    -e HOST=www.baidu.com \
    --entrypoint="/docker-entrypoint.sh && envsubst '$${HOST}' < /etc/nginx/default.template > /etc/nginx/conf.d/default.conf" \
    nginx:1.22.0
    -c "envsubst '${HOST}' < /etc/nginx/default.template > /etc/nginx/default.conf"

    docker run -d  \
    --name nginx \
    --privileged \
    --restart unless-stopped \
    -m 200m \
    -v $PWD/nginx/nginx.conf:/etc/nginx/nginx.conf \
    -v $PWD/nginx/conf.d:/etc/nginx/conf.d \
    -v $PWD/nginx/default.template:/etc/nginx/default.template \
    -v $PWD/nginx/html:/usr/share/nginx/html \
    -v $PWD/nginx/logs:/var/log/nginx \
    -p 8001:80 \
    -e HOST=www.baidu.com \
    --entrypoint="/docker-entrypoint.sh && envsubst '${HOST}' < /etc/nginx/default.template > /etc/nginx/conf.d/default.conf" \
    nginx:1.22.0
```

联合navieproxy生成的证书一起使用。
如果不需要开启ssl功能，自行注释调docker-compose.yaml文件中command命令行中的
```shell
&& envsubst \
         '{{$$HOST $$CRT_PATH  $$KEY_PATH}}' \
         < /etc/nginx/conf.d/ssl.template \
         > /etc/nginx/conf.d/ssl.conf \
```

docker 每次启动都会去执行docker-compose.yaml中的`command`命令，所以如果对文件有更改，不要使用`command`。