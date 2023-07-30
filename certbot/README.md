在每个月的第一个日替换证书

```shell
0 0 1 * * /bin/bash /path/to/renew-certs.sh >> /var/log/renew-certs.log 2>&1
```

[Welcome to certbot-dns-cloudflare’s documentation!](https://certbot-dns-cloudflare.readthedocs.io/en/stable/)

[Setup SSL with Docker, NGINX and Lets Encrypt](https://www.programonaut.com/setup-ssl-with-docker-nginx-and-lets-encrypt/)

申请太多会失败，失败原因如下：
```json
{
  "type": "urn:ietf:params:acme:error:rateLimited",
  "detail": "Error creating new order :: too many certificates (5) already issued for this exact set of domains in the last 168 hours: *.test.com, retry after 2023-07-31T15:03:39Z: see https://letsencrypt.org/docs/duplicate-certificate-limit/",
  "status": 429
}
```