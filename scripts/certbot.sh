#!/bin/bash

#colors
RED='\033[1m\033[31m'
GREEN='\033[1m\033[32m'
YELLOW='\033[1m\033[33m'
MAGENTA='\033[1m\033[35m'
CYAN='\033[1m\033[36m'
NC='\033[0m' # No Color

#maximum number of reTRIES
MAXRETRIES=5

#timeout
TIMEOUT=5

CERTBOT_CMD=/usr/local/bin/certbot
LE_DIR=/etc/letsencrypt/live

if [ "$DEBUG" = "1" ]; then
	set -x
fi

printf "|---------------------------------------------------------------------------------------------\n";
printf "| ${GREEN}Let's Encrypt started${NC}\n";
printf "| I will use $CERTBOT_EMAIL for certificate registration with certbot.\n";
printf "| This e-mail is used by Let's Encrypt when you lose the account and want to get it back.\n";
printf "|---------------------------------------------------------------------------------------------\n";

# Include functions
. /scripts/functions

#common arguments
args=("-n" "-m" "$CERTBOT_EMAIL" "--agree-tos" "-a" "certbot-route53:auth" "--rsa-key-size" "4096" "--redirect" "--hsts" "--staple-ocsp")

#if we are in a staging enviroment append the staging argument, the staging argument
#was previously set to an empty string if the staging enviroment was not used
#but this confuses cert-auto and should hence not be used
if [ "$CERTBOTMODE" ]; then
  printf "| ${RED}Staging environment of Let's Encrypt is activated!${NC}\n";
  printf "| ${RED}The generated certificates won't be trusted. But you will not reach Let’s Encrypt's rate limits.${NC}\n";
  args+=("--test-cert");
fi

#we need to be careful and don't reach the rate limits of Let's Encrypt https://letsencrypt.org/docs/rate-limits/
#Let's Encrypt has a certificates per registered domain (20 per week) and a names per certificate (100 subdomains) limit
#so we should create ONE certificiates for a certain domain and add all their subdomains (max 100!)

for d in $(env | grep 'DOMAIN_'); do
  varName=$(echo $d|awk -F '[=]' '{print $1}')
  varValue=$(echo $d|sed "s/^${varName}=//")
  if [[ "$varValue" == "" ]]; then
    printf "| CERTS: ${YELLOW}${varName} value is empty, ignoring${NC}\n"
    continue
  fi
  mainDomain=$(echo $varValue|awk -F '[,]' '{print $1}')
  # Convert wildcard certificate name from *.example.com to wildcard.example.com
  CERT_NAME=$(echo $mainDomain|sed 's/^*./wildcard./g')
  printf "| CERTS: ${varName}: ${GREEN}Primary domain: $mainDomain ${NC}\n"
  printf "| CERTS: ${varName}: ${YELLOW}Validating domain(s): $varValue ${NC}\n"
  DOMAIN_DIR="${LE_DIR}/${CERT_NAME}";
  dom="";
  for i in $(echo $varValue|sed 's/,/ /g')
  do
    let exitcode=TRIES=0
    echo '0' > /tmp/validation_complete_${CERT_NAME}
    until [ $TRIES -ge $MAXRETRIES ]
    do
      TRIES=$[$TRIES+1]
      if [[ "$(cat /tmp/validation_complete_${CERT_NAME})" != "1" ]]; then
        $CERTBOT_CMD certonly --dry-run "${args[@]}" -d "$i" 2>/dev/null | grep -q 'The dry run was successful.' && break
        exitcode=$?

        if [ $TRIES -eq $MAXRETRIES ]; then
          printf "| CERTS: ${varName}: $i: ${RED}Unable to verify domain ownership after ${TRIES} attempts.${NC}\n"
        else
          printf "| CERTS: ${varName}: $i: ${MAGENTA}# ${TRIES}${NC}: ${RED}Unable to verify domain ownership, we try again in ${TIMEOUT} seconds.${NC}\n"
          sleep $TIMEOUT
        fi
      fi
    done

    if [ $exitcode -eq 0 ]; then
      printf "| CERTS: ${varName}: ${GREEN}Domain successfully validated: $i ${NC}\n"
      dom="$dom -d $i"
      echo '1' > /tmp/validation_complete_${CERT_NAME}
    fi
  done

  #only if we have successfully validated at least a single domain we have to continue
  if [ -n "$dom" ]; then
    # check if DOMAIN_DIR exists, if it exists use --cert-name to prevent 0001 0002 0003 folders
    domains=$(echo $dom|sed 's/-d / /g')
    printf "| CERTS: ${varName}: Using domain(s) for generating certificate: ${YELLOW}${domains}${NC}\n"
    if [ -d "$DOMAIN_DIR" ]; then
      printf "| CERTS: ${varName}: CERTBOT CMD: ${MAGENTA}certbot certonly %s --cert-name %s ${NC}\n" "${args[*]}" "${CERT_NAME} $dom";
      $CERTBOT_CMD certonly "${args[@]}" --cert-name "${CERT_NAME}" $dom 2>&1 | sed "s/^/| CERTS: ${varName}: CERTBOT: /"
    else
      printf "| CERTS: ${varName}: CERTBOT CMD: ${MAGENTA}certbot certonly %s ${NC}\n" "${args[*]} $dom";
      $CERTBOT_CMD certonly "${args[@]}" $dom 2>&1 | sed "s/^/| CERTS: ${varName}: CERTBOT: /"
    fi
  fi
done

#prepare renewcron
if [ "$CERTBOTMODE" ]; then
  printf "SHELL=/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\nPROXY_ADDRESS=$PROXY_ADDRESS\nCERTBOTMODE=$CERTBOTMODE\n" > /etc/cron.d/renewcron 
else
  printf "SHELL=/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\nPROXY_ADDRESS=$PROXY_ADDRESS\n" > /etc/cron.d/renewcron 
fi

declare -a arr=$CERTBOT_CRON_RENEW;
for i in "${arr[@]}"
do
  printf "$i root /bin/bash $BASH_CMD_FLAGS /scripts/renewAndSendToProxy.sh > /var/log/dockeroutput.log\n" >> /etc/cron.d/renewcron
done

printf "\n" >> /etc/cron.d/renewcron

# send current certificates to proxy - after that do a certbot renew round (which could take some seconds) and send updated certificates to proxy (faster startup with https when old certificates are still valid)
printf "| CERTS: ${GREEN}Sending certificates to $PROXY_ADDRESS for all domains...${NC}\n"
sendCertsToProxy "$PROXY_ADDRESS"
printf "|---------------------------------------------------------------------------------------------\n";
