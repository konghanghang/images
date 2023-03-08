在每个月的第一个日替换证书

```shell
0 0 1 * * /bin/bash /path/to/renew-certs.sh >> /var/log/renew-certs.log 2>&1
```