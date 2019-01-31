#!/bin/bash

#colors
RED='\033[1m\033[31m'
GREEN='\033[1m\033[32m'
YELLOW='\033[1m\033[33m'
MAGENTA='\033[1m\033[35m'
CYAN='\033[1m\033[36m'
NC='\033[0m' # No Color

#timeout
TIMEOUT=5

CERTBOT_CMD=/usr/local/bin/certbot
LE_DIR=/etc/letsencrypt/live

if [ "$DEBUG" = "1" ]; then
	set -x
fi

#
# Main
#

# Include functions
. /scripts/functions
printf "|---------------------------------------------------------------------------------------------\n";
printf "| Today is $(date)${NC}\n"
printf "| I will renew and send certificates to these proxy services: ${YELLOW}$PROXY_ADDRESS${NC}\n";
printf "|---------------------------------------------------------------------------------------------\n";

# Lets attempt to renew all existing certificates
printf "| CERTBOT: ${GREEN}Renewing certificates for all domains...${NC}\n"
eval "$CERTBOT_CMD renew -n -agree-tos -m $CERTBOT_EMAIL -a 'certbot-route53:auth' 2>&1 | sed 's/^/| CERTBOT: /'"

printf "| CERTS: ${GREEN}Sending updated certificates to $PROXY_ADDRESS for all domains...${NC}\n"
sendCertsToProxy "$PROXY_ADDRESS"
printf "|---------------------------------------------------------------------------------------------\n";
