# images
存放自己日常使用的镜像

## 创建网络
所有的镜像都跑在mynet网络下，所以在使用前先创建网络：
`--gateway`可以不用指定，默认拿该网段的第一个地址。
### ipv4
```shell
docker network create --driver bridge --subnet 192.168.6.0/24 --gateway 192.168.6.1 mynet
```
### ipv6
需要先开启docker的ipv6支持。编辑/etc/docker/daemon.json修改为以下内容：
```json
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00:d1::/64",
  "experimental": true
}
```
修改后需要对docker进行重启。然后再创建自己的桥接网络。daemon.json中配置的ipv6子网段不要和新建的桥接网络子网段重复，比如daemon.json中的为`fd00:d1::/64`，下边新的桥接网络中为`fd00:dd::/64`。
```shell
docker network create --driver bridge --subnet fd00:dd::/64 --gateway fd00:dd::1 mynet
```
### ipv4&ipv6
```shell
docker network create --driver=bridge --subnet=192.168.6.0/24  --subnet=fd00:dd::/64 --ipv6 mynet
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
关于配置中的`"acceptProxyProtocol": true,`说明：
```json
{
    "port": 13101,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
        "clients": [
        {
            "id": "c541c9fe-fa75-4b28-d839-497a28a41de2",
            "level": 0,
            "email": "vlessws@test.com"
        }
        ],
        "decryption": "none"
    },
    "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
            "acceptProxyProtocol": true,// 在使用直连13101d端口的时候需要把这个去掉，要不然会导致连不上
            "path": "/vlessws13101"
        }
    },
 }
```

## swag-xray
后来发现了swag容器，来自linuxserver,它里边原先有php，因为我不需要php，所以使用官方`1.27.0`的版本进行php剔除。然后再加入xray组成。

因为swag中已经自带nginx和证书更新功能，所以基本是全自动完成，证书续期也不用我们手动来执行了。

build步骤：
```shell
docker build -t konghanghang/swag:1.27.0-amd64 -f Dockerfile --build-arg VERSION=1.27.0 .
docker push konghanghang/swag:1.27.0-amd64

# arm的暂时没有跑成功
docker build -t konghanghang/swag:1.27.0-arm32v7 -f Dockerfile.armhf --build-arg VERSION=1.27.0 .
docker push konghanghang/swag:1.27.0-arm32v7

docker build -t konghanghang/swag:1.27.0-arm64v8 -f Dockerfile.aarch64 --build-arg VERSION=1.27.0 .
docker push konghanghang/swag:1.27.0-arm64v8

docker manifest create \
> konghanghang/swag:1.27.0 \
> --amend konghanghang/swag:1.27.0-amd64 \
> --amend konghanghang/swag:1.27.0-arm32v7 \
> --amend konghanghang/swag:1.27.0-arm64v8
```

使用说明：
1. 修改`.env`文件中的url为自己的二级域名，xray_domain为分配给xray的三级域名前缀，EMAIL为自己的邮箱

## subconverter
后端地址：[subconverter](https://github.com/tindy2013/subconverter)

前端地址：[sub-web](https://github.com/CareyWang/sub-web)
