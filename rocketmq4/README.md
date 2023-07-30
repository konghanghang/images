# rocketmq4

使用的版本为4.9.4.

克隆仓库到机器后，需要修改logs和store目录的权限为777，不然broker可能会无法启动。自己的系统是ubuntu,pull镜像启动提示
```shell
CONTAINER ID   IMAGE                           COMMAND                  CREATED         STATUS                            PORTS                                                                   NAMES
534bfa54b310   apache/rocketmq:4.9.4           "sh mqbroker -c /etc…"   3 minutes ago   Restarting (253) 35 seconds ago                                                                           rmqbroker
```
修改权限后正常运行。
