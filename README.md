# images
存放自己日常使用的镜像

## 创建网络
所有的镜像都跑在mynet网络下，所以在使用前先创建网络：
```shell
docker network create --driver bridge --subnet 192.168.5.0/24 --gateway 192.168.5.1 mynet
```

## nginx-ray
nginx-xray是最先研究的一个镜像，本镜像需要自己在机器上安装`cerbot`来进行证书的签发，不是很自动化，只做记录。

由于不是很自动化，所以需要进行以下手动设置的：
1. `.env`需要手动指定`XRAY_HOST`
2. 在xray/config.json中需要修改证书配置路径，修改里边的域名地址:${XRAY_HOST},因为没有找到方法替换容器中的环境变量进去，所以只能手动改。如果有什么好的办法也可以告诉我，多谢！
    ```json
    "certificates": [
        {
        "certificateFile": "/etc/letsencrypt/live/${XRAY_HOST}/fullchain.pem",
        "keyFile": "/etc/letsencrypt/live/${XRAY_HOST}/privkey.pem"
        }
    ]
    ```

## swag-xray
后来发现了swag容器，来自linuxserver,它里边原先有php，因为我不需要php，所以使用官方`1.27.0`的版本进行php剔除。然后再加入xray组成。

因为swag中已经自带nginx和证书更新功能，所以基本是全自动完成，证书续期也不用我们手动来执行了。

使用说明：
1. 修改`.env`文件中的url为自己的二级域名，xray_domain为分配给xray的三级域名前缀，EMAIL为自己的邮箱

## subconverter
后端地址：[subconverter](https://github.com/tindy2013/subconverter)
前端地址：[sub-web](https://github.com/CareyWang/sub-web)