FROM ubuntu:16.04
LABEL MAINTAINER satish@satishweb.com 

#set default env variables
ENV DEBIAN_FRONTEND=noninteractive \
    CERTBOT_EMAIL="" \
    PROXY_ADDRESS="proxy" \
    CERTBOT_CRON_RENEW="('0 3 * * *' '0 15 * * *')" \
    PATH="$PATH:/root"

RUN apt-get update \
	&& apt-get -y install \
		cron \
		supervisor \
		curl \
		python \
		openssl \
		ca-certificates \
		python-pip \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# This installs certbot and route53 plugin both
RUN pip install certbot-dns-route53

# Add supervisord.conf
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf 

# Add scripts and make it executable
COPY scripts /scripts
RUN chmod u+x /scripts/*

# Add docker entrypoint script and make it executable
ADD docker-entrypoint /docker-entrypoint
RUN chmod u+x /docker-entrypoint

RUN ln -sf /proc/1/fd/1 /var/log/dockeroutput.log

# Add symbolic link in cron.daily directory without ending (important!)
RUN touch /etc/cron.d/renewcron
RUN chmod u+x /etc/cron.d/renewcron

# Run the command on container startup
CMD ["/docker-entrypoint"]
