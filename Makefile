IMAGE?=satishweb/docker-flow-proxy-cert-manager-letsencrypt-aws-route53
PLATFORMS?=linux/amd64,linux/arm64,linux/arm/v7,linux/arm/v6
WORKDIR?=$(shell pwd)
TAGNAME?=$(shell curl -s https://pypi.org/pypi/certbot/json|jq -r '.info.version')
ifdef PUSH
	EXTRA_BUILD_PARAMS = --push-images --push-git-tags
endif

ifdef LATEST
	EXTRA_BUILD_PARAMS += --mark-latest
endif

all:
	./build.sh \
	  --image-name "${IMAGE}" \
	  --platforms "${PLATFORMS}" \
	  --work-dir "${WORKDIR}" \
	  --git-tag "${TAGNAME}" \
	  ${EXTRA_BUILD_PARAMS}
