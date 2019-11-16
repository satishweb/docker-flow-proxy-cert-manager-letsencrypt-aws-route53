# Lets Encrypt Docker Image for Docker Flow Proxy

## Features
- Integration with LetsEncrypt and AWS Route53 DNS for Docker Flow Proxy (https://proxy.dockerflow.com/)
- Inspired by: https://github.com/hamburml/docker-flow-letsencrypt
- Cronjob to renew certificate every day if certificate is near expiry
- Support for custom script execution (/app-config)
- Support for linux/amd64,linux/arm64,linux/arm/v7,linux/arm/v6
- Alpine based tiny images

# How to use
## Docker run Command
```
docker run --rm -it --name cert-manager \
    -e DOMAIN_1="test.satishweb.com,test1.satishweb.com"\
    -e DOMAIN_2="test2.satishweb.com"\
    -e DOMAIN_3="*.satishweb.com"\
    -e CERTBOT_EMAIL="webmaster@satishweb.com" \
    -e PROXY_ADDRESS="proxy" \
    -e CERTBOTMODE="staging" \
    -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
    -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    -e AWS_REGION=${AWS_REGION} \
    -e AWS_HOSTED_ZONE_ID=${AWS_HOSTED_ZONE_ID} \
    -v $(pwd)/data/letsencrypt:/etc/letsencrypt \
satishweb/docker-flow-proxy-cert-manager-letsencrypt-aws-route53:latest
```
## Variables list
- `DOMAIN_*`: Comma separated subdomains list.
  - All domains must have same parent domain
  - When wildcard is used, only one domain is expected
- `CERTBOT_EMAIL`: Email address used for lets encrypt registration
- `PROXY_ADDRESS`: Comma separated list of Docker Flow Proxy addresses
  - Accepted values are:
    - `proxy`: Hostname of Docker Flow Proxy. It must be accessible from container
    - `proxy.domain.com`: FQDN of Docker Flow Proxy
    - `http://proxy:8080/v1/docker-flow-proxy/cert`: API path for Docker Flow Proxy
- `CERTBOTMODE`: Declare this variable and lets encrypt goes into stage/test mode
- `AWS_ACCESS_KEY_ID`: AWS Access Key from AWS Console - IAM
- `AWS_SECRET_ACCESS_KEY`: AWS Secret Key from AWS Console - IAM
- `AWS_REGION`: AWS Region
- `AWS_HOSTED_ZONE_ID`: Domain DNS Zone ID from Route53 service
- `CERTMGR_DISABLE`: set this to yes to disable cert manger but keep container running
- `PROXY_PORT`: Set this to a custom number if you have changed defualt api port on Docker Flow Proxy
## Docker Stack configuration:

```
  cert-manager:
    image: satishweb/docker-flow-proxy-cert-manager-letsencrypt-aws-route53
    hostname: cert-manager
    network:
      - proxy
    environment:
      - DOMAIN_1="test.satishweb.com,test1.satishweb.com"
      - DOMAIN_2="test2.satishweb.com"
      - DOMAIN_3="*.satishweb.com"
      - CERTBOT_EMAIL=webmaster@satishweb.com
      - PROXY_ADDRESS=proxy
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_REGION=${AWS_REGION}
      - AWS_HOSTED_ZONE_ID=${AWS_HOSTED_ZONE_ID}
      - CERTBOTMODE="staging"
      # Comment above line to go in production mode
    volumes:
      - ./data/certs:/etc/letsencrypt
      # Add your custom code to be run 
      # - ./app-config:/app-config
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
## Build the Dockerfile
```
docker build . --no-cache -t satishweb/docker-flow-proxy-cert-manager-letsencrypt-aws-route53
```
## Test the scripts without rebuilding container image
- Set the AWS variables required by container and export it
- Change satishweb.com to your domain name in below code and run it
```
docker run --rm -it --name cert-manager \
    -e DOMAIN_1="test.satishweb.com,test1.satishweb.com"\
    -e DOMAIN_2="test2.satishweb.com"\
    -e DOMAIN_3="*.satishweb.com"\
    -e CERTBOT_EMAIL="webmaster@satishweb.com" \
    -e PROXY_ADDRESS="proxy" \
    -e CERTBOTMODE="staging" \
    -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
    -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    -e AWS_REGION=${AWS_REGION} \
    -e AWS_HOSTED_ZONE_ID=${AWS_HOSTED_ZONE_ID} \
    -v $(pwd)/data/letsencrypt:/etc/letsencrypt \
    -v $(pwd)/docker-entrypoint:/docker-entrypoint \
    -v $(pwd)/certbot.sh:/certbot.sh \
satishweb/docker-flow-proxy-cert-manager-letsencrypt-aws-route53:latest
```