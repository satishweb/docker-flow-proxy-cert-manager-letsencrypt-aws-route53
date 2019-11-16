FROM alpine:latest
LABEL MAINTAINER satish@satishweb.com

RUN apk --no-cache add \
        bash \
        openssl \
        curl \
        python3 \
        alpine-sdk \
        gcc \
        linux-headers \
        openssl-dev \
        libffi-dev \
        python3-dev \
    && pip3 install --upgrade pip \
    && pip3 install acme==0.40.0 \
    && pip3 install certbot-dns-route53 \
    && apk del --purge \
        alpine-sdk \
        gcc \
        libffi-dev \
        python3-dev \
        linux-headers

# Add scripts and make it executable
ADD docker-entrypoint /docker-entrypoint
ADD certbot.sh /certbot.sh
RUN chmod u+x /docker-entrypoint /certbot.sh

# Run the command on container startup
ENTRYPOINT ["/docker-entrypoint"]
CMD [ "/bin/bash", "-c", "/certbot.sh" ]

# Healthcheck
HEALTHCHECK --interval=5m --timeout=10s --start-period=10s CMD [[ $(cat /tmp/status|grep -q '1') ]] || exit 1
