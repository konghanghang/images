#!/bin/bash

# 运行 certbot renew 命令
docker-compose exec certbot certbot renew

# 如果更新成功，重新启动服务
if [ $? -eq 0 ]
then
    docker-compose restart nginx
fi