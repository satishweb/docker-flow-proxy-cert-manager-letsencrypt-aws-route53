# Docker container for Certificate Management 
- Integration with LetsEncrypt and AWS Route53 DNS for Docker Flow Proxy (https://proxy.dockerflow.com/)
- Inspired by: https://github.com/hamburml/docker-flow-letsencrypt

## Simple Test Run

```
docker run --rm -it --name cert-manager \
    -e DOMAIN_1="test.yourdomain.com,test1.yourdomain.com"\
    -e DOMAIN_2="test2.yourdomain.com"\
    -e CERTBOT_EMAIL="webmaster@yourdomain.com" \
    -e PROXY_ADDRESS="proxy" \
    -e CERTBOT_CRON_RENEW="('0 3 * * *' '0 15 * * *')"\
    -e CERTBOTMODE="staging" \
	-e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
	-e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
	-e AWS_REGION=${AWS_REGION} \
	-e AWS_HOSTED_ZONE_ID=${AWS_HOSTED_ZONE_ID} \
	-v $(pwd)/data/letsencrypt:/etc/letsencrypt \
satishweb/docker-flow-proxy-cert-manager-letsencrypt-aws-route53:latest
```

## Docker Stack configuration:

```
  cert-manager:
    image: satishweb/docker-flow-proxy-cert-manager-letsencrypt-aws-route53
    hostname: cert-manager
	network:
	  - proxy
	environment:
      - DOMAIN_1="test.yourdomain.com,test1.yourdomain.com"
      - DOMAIN_2="test2.yourdomain.com"
      - CERTBOT_EMAIL=webmaster@yourdomain.com
      - PROXY_ADDRESS=proxy
      - CERTBOT_CRON_RENEW="('0 3 * * *' '0 15 * * *')"
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_REGION=${AWS_REGION}
      - AWS_HOSTED_ZONE_ID=${AWS_HOSTED_ZONE_ID}
      - CERTBOTMODE="staging"
      # Comment above line to go in production mode
    volumes:
      - ${DATA_DIR}/certs:/etc/letsencrypt
    deploy:
      replicas: 1
      # labels:
      #   - com.df.servicePath=/.well-known/acme-challenge
      #   - com.df.notify=true
      #   - com.df.distribute=true
      #   - com.df.port=80
      placement:
        constraints:
          - node.role==manager
          # This container can be run on any swarm node
    labels:
      - "com.satishweb.description=Certificate Manager"
```
## Run certbot container but disable its execution
- Add `CERTBOT_DISABLE=yes` variable to the docker environment list
