#!/bin/bash
# This is a daemon script, never exits unless there is an error

if [ "$DEBUG" = "1" ]; then
  set -x
fi

# Functions
__validations() {
  if [ "$CERTBOTMODE" ]; then
    printf "| ${YELLOW}Staging env of Let's Encrypt is activated!${NC}\n";
    printf "| ${YELLOW}The generated certificates won't be trusted.${NC}\n";
    args+=("--test-cert");
  fi

  # warn user about deprecated CERTBOT_CRON_RENEW variable
  if [[ "$CERTBOT_CRON_RENEW" != "" ]]; then
    printf "| CERTS: ${YELLOW}CERTBOT_CRON_RENEW is deprecated.\n";
    printf "         Cerbot script is daemonized and certificate renewal and";
    printf "         push to proxy is now attempted every 24 hours${NC}\n";
  fi
}

__generateCombinedCert() {
  # $1 = Domain

  if [[ "$1" == "" ]]; then
    echo "| ${RED}ERR: __generateCombinedCert: Missing params${NC}"
    sleep 120
    exit 1
  fi

  domainCertDir=${LE_DIR}/${1}
  if [[ -f "${domainCertDir}/cert.pem" ]]; then
    cat ${domainCertDir}/cert.pem \
        ${domainCertDir}/chain.pem \
        ${domainCertDir}/privkey.pem \
    > ${domainCertDir}/${1}.combined.pem 2>/dev/null
  else
    printf "| CERTS: ${1}: ${YELLOW}Domain $certs are not available yet,${NC}\n"
    printf "|              ${YELLOW}skipping ...${NC}\n"
    # We have a situation, certificates were not available at last certbot run
    # We can not wait for 24 hours for next renewal. So lets renew certs again
    # in 5 mins
    RENEW_INTERVAL=300 # Retry again after 300 seconds
    break
  fi
}

__pushDomainCertToProxy() {
  # $1 = Domain name. Certificates of this domain will be sent to proxies
  # $2 = Proxy server address list separated by space

  # returns exitcode variable
  if [[ "$2" == "" ]]; then
    echo "| ${RED}ERR: __pushDomainCertToProxy: Missing params${NC}"
    sleep 120
    exit 1
  fi

  for a in $2
  do
    proxyName=$(echo $a|awk -F '[:/]' '{print $4"-"$5}')
    printf "| CERTS: ${1}:  ${MAGENTA}# ${TRIES}${NC}: ";
    printf "Sending certificate to ${GREEN}${a} ...${NC}";
    curl --silent -i -XPUT \
      --data-binary @${LE_DIR}/${1}/${1}.combined.pem \
      "${a}?certName=${1}.combined.pem&distribute=true"\
    > /dev/null 2>&1
    exitcode="$?" 2>/dev/null
    if [[ "$exitcode" != "0" ]]; then
      printf "     ${RED}[ FAILED ]${NC}\n";
      RENEW_INTERVAL=300 # Retry again after 300 seconds
    else
      printf "     ${GREEN}[ OK ]${NC}\n"
    fi
  done
}

__updateProxies() {
  # $1 = PROXY urls list

  if [[ "$1" == "" ]]; then
    echo "| ERR: ${RED}__updateProxies: Proxy servers url list is empty${NC}"
    sleep 120
    exit 1
  fi

  for d in $(cd $LE_DIR;find . -mindepth 1 -maxdepth 1 -type d\
            |sed 's/^.\///;s/^*./wildcard./g'\
            |tr '\n' ' '); do
    #concat certificates
    DOMAIN_CERT_PATH=${LE_DIR}/${d}
    __generateCombinedCert "${d}"

    TRIES=0
    exitcode=0
    until [ $TRIES -ge $MAX_RETRIES ]
    do
      TRIES=$[$TRIES+1]
      __pushDomainCertToProxy "${d}" "$1"
      # above function returns exitcode variable
      if [[ "$exitcode" != "0" ]]; then
        printf "| CERTS: ${d}: ${RED}At least 1 proxy did not accept ";
        printf "the certificates${NC}\n";
        if [[ "$TRIES" != "$MAX_RETRIES" ]]; then
          sleep ${RETRY_INTERVAL}
        else
          printf "| CERTS: ${d}: ${GREEN}Exceeded max retries: "
          printf "${MAX_RETRIES} ${NC}\n";
        fi
      else
        printf "| CERTS: ${d}: ${GREEN}Certs received by all proxies:${NC}\n";
        printf"|             ${GREEN}${1} ${NC}\n"
        break
      fi
    done
  done
}

__validateDomainAndGenCerts() {
  # $1 = Comma separated domains list
  # $2 = Label

  if [[ "$2" == "" ]]; then
    echo "| ERR: ${RED}__validateDomainAndGenCerts: Missing params${NC}"
    sleep 120
    exit 1
  fi

  wildcard=$(echo "$1"|grep '*.'|wc -l)
  # Convert wildcard certificate name: *.example.com to wildcard.example.com
  mainDomain=$(echo $1|awk -F '[,]' '{print $1}')
  if [[ "$wildcard" == "1" && \
        "$(echo $mainDomain|grep '*.'|wc -l)" == "1" && \
        "$(echo $1| awk -F'[,]' '{print NF-1}')" == "0" ]]; then
    # This is a wildcard certficate, no SAN support
    mainDomain=$(echo $mainDomain|sed 's/^*./wildcard./g')
  elif [[ "$wildcard" == "1" ]]; then
    # It appears that one of the subdomain in list is with a wildcard (*).
    # We expect only one domain in list when wildcard is used.
    # We must exit here as we have a bad input
    printf "| CERTS: ${2}: ${RED}ERR: This variable got a wildcard domain: ${2}"
    printf "${NC}\n";
    printf "| CERTS: ${2}: ${RED}ERR: We expect only one entry when "
    printf "wildcard is used${NC}\n"
    sleep 120
    exit 1
  fi

  # Get parent domain name
  parentDomain=$(echo $mainDomain\
                |awk -F '[,]' '{print $1}'\
                |awk -F '[.]' '{print $(NF-1)"."$(NF)}')

  # Lets validate the parent domain
  let exitcode=TRIES=0
  until [ $TRIES -ge $MAX_RETRIES ]
  do
    TRIES=$[$TRIES+1]
    if [[ -f /tmp/validation_complete_${parentDomain} ]]; then
      printf "| CERTS: ${2}: ${GREEN}Primary domain already validated: "
      printf "${parentDomain} ${NC}\n";
      break
    else
      printf "| CERTS: ${2}: ${GREEN}Primary domain: ${parentDomain} ${NC}\n";
      printf "| CERTS: ${2}: ${YELLOW}Validating: ${parentDomain} ...${NC}\n";
      $CERTBOT_CMD certonly \
        --dry-run "${args[@]}" \
        -d "${parentDomain}" 2>/dev/null \
      | grep -q 'The dry run was successful.'
      exitcode=$?
      if [[ "$exitcode" == "0" ]]; then
        printf "| CERTS: ${2}: ${GREEN}Domain successfully validated: ";
        printf "${parentDomain}${NC}\n"
        touch /tmp/validation_complete_${parentDomain}
        break
      fi
      if [ $TRIES -eq $MAX_RETRIES ]; then
        printf "| CERTS: ${parentDomain}: ${RED}Unable to verify parent domain";
        printf " ownership after ${TRIES} attempts.${NC}\n";
      else
        printf "| CERTS: ${parentDomain}: ${MAGENTA}# ${TRIES}: ";
        printf "Unable to verify parent domain ownership. ";
        printf "we will try again in ${RETRY_INTERVAL} seconds.${NC}\n";
        sleep ${RETRY_INTERVAL}
      fi
    fi
  done

  if [[ "$exitcode" != "0" ]]; then
    # Domain validation failed, no point continuring further
    return 1
  fi

  # Lets prepare domains list for new certificate
  domainsAsSAN=""
  for i in $(echo $1|sed 's/,/ /g')
  do
    # If i value is empty, ignore it
    [[ "$i" == "" ]] && continue
    # Ensure parentdomain matches
    pDom="$(echo $i|awk -F '[.]' '{print $(NF-1)"."$(NF)}')"
    if [[ "${pDom}" != "${parentDomain}" ]]; then
      printf "| CERTS: ${parentDomain}: ${RED}Parent domain do not match ";
      printf "for $i, ignoring...${NC}\n";
      continue
    fi
    domainsAsSAN+=" $i"
  done

  # Need at least one domain to go for certificate
  if [[ "${domainsAsSAN}" != "" ]]; then
    # Continue only if we have at least one domain validated
    __getCertificates "$domainsAsSAN" "${mainDomain}" "${2}"
  fi
}

__getCertificates() {
  # $1 = SAN Domains list
  # $2 = Cert Name or domain name
  # $3 = Label

  if [[ "$3" == "" ]]; then
    echo "| ERR: ${RED}__getCertificates: Missing params${NC}"
    sleep 120
    exit 1
  fi

  if [ -n "$1" ]; then
    # check if domain Lets encrupt dir path exists, if it exists use
    # --cert-name to prevent 0001 0002 0003 folders
    cbDomArgs=""; for v in $1; do cbDomArgs+=" -d $v"; done
    printf "| CERTS: ${3}: Using domain(s) for generating certificate:"
    printf " ${YELLOW}${1}${NC}\n"
    if [ -d "${LE_DIR}/$2" ]; then
      cbCmd="$CERTBOT_CMD certonly ${args[@]} --cert-name '${2}' ${cbDomArgs}"
    else
      cbCmd="$CERTBOT_CMD certonly ${args[@]} ${cbDomArgs}"
    fi
    printf "| CERTS: ${3}: CMD: ${MAGENTA}${cbCmd}${NC}\n";
    eval ${cbCmd} 2>&1 | sed "s/^/| CERTS: ${3}: CERTBOT: /"
  fi
}

__processDomainEnvVarsAndGenCerts() {
  # $1 = Domain Variables list (DOMAIN_*)

  if [[ "$1" == "" ]]; then
    echo "| ERR: ${RED}__processDomainEnvVarsAndGenCerts: Missing params${NC}"
    sleep 120
    exit 1
  fi

  for d in $1; do
    varName=$(echo $d|awk -F '[=]' '{print $1}')
    varValue=$(echo $d|sed "s/^${varName}=//")
    if [[ "$varValue" == "" ]]; then
      printf "| CERTS: ${YELLOW}${varName} value is empty, ignoring${NC}\n";
      continue
    fi
    __validateDomainAndGenCerts "$varValue" "$varName"
  done
}

__generateProxyUrls() {
  # $1 = Proxy servers
  # $2 = Default proxy port

  # Returns ${proxyServerUrls}

  if [[ "$1" == "" ]]; then
    echo "| ERR: ${RED}__generateProxyUrls: Missing params${NC}"
    sleep 120
    exit 1
  fi

  # Lets generate proxy host address urls array
  proxyPath="v1/docker-flow-proxy/cert"
  proxyServerUrls=""
  for a in $(echo $1|sed 's/,/ /g')
  #$(echo $1|awk -F '[,]' '{print $1}'|awk -F '[.]' '{print $(NF-1)"."$(NF)}')
  do
    # Lets check if proxy address is a url or hostname with port specified
    # Use default if not specified
    # This is for backward compatibility
    if [[ $a == *"https://"* || $a == *"http://"* ]]; then
      # Proxy address is actually an url, assume that its docker flow proxy url
      proxyServerUrls+=" $a"
    elif [[ "$(echo $i|awk -F '[:]' '{print $2}')" != "" ]]; then
      # Proxy address is not a url but has port
      # Assume default http as protocol
      host=$(echo $i|awk -F '[:]' '{print $1}')
      port=$(echo $i|awk -F '[:]' '{print $2}')
      if ! [[ $port =~ ^[0-9]+$ ]]; then
        echo "| ${RED}ERR: Proxy server has invalid port: ${a}${NC}"
        sleep 120
        exit 1
      fi
    else
      # no url or port number in proxy address, assume its just the hostname
      # This satisfies the backward compatibility
      proxyServerUrls+=" http://${a}:${PROXY_PORT}/${proxyPath}"
    fi
  done
}

__renewCertLoop() {
  sleep $RENEW_INTERVAL

  # After every RENEW_INTERVAL seconds, we will attempt renewal and
  # resend of the certificates to proxy
  while true
  do
    if [[ "${failCount}" == "${maxFailCount}" ]]; then
      echo "| WARN: We exceed the maximum failures allowed: ${maxFailCount}"
      echo "|       This container is now unhealthy"
    fi
    printf "| CERTBOT: ${GREEN}Attempting to ";
    printf "renew certificates for all domains...${NC}\n"
    eval "$CERTBOT_CMD renew \
      -n \
      -agree-tos \
      -m $CERTBOT_EMAIL \
      -a 'certbot-route53:auth' 2>&1 \
      | sed 's/^/| CERTBOT: /'"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
      # Certbot command was failed, we need to retry again
      RENEW_INTERVAL=300
      let failCount++
    fi
    __updateProxies "${proxyServerUrls}"
    # Lets reset renew interval and renew certs back to original values
    RENEW_INTERVAL=86400 # 1 day
  done
}

__printLine() {
  printf "|----------------------------------------------------------------\n";
}

## Main

# maximum number of reTRIES
MAX_RETRIES=5
RETRY_INTERVAL=10 # Timeout in seconds for proxy communication retries

CERTBOT_CMD=certbot
LE_DIR=/etc/letsencrypt/live

__validations
# common arguments
args=("-n" "-m" "$CERTBOT_EMAIL" "--agree-tos" "-a" "certbot-route53:auth" \
      "--rsa-key-size" "4096" "--redirect" "--hsts" "--staple-ocsp")
__printLine
printf "| INFO: ${GREEN}Let's Encrypt started${NC}\n";
printf "| INFO: I will use $CERTBOT_EMAIL for registration with Lets Encrypt.\n";
__printLine

# we need to be careful and don't reach the rate limits of Let's Encrypt
# https://letsencrypt.org/docs/rate-limits/
# Let's Encrypt has a limit of 20 certificates per week for each registered
# domain and 100 subdomains per domain
# So best option is to create wildcard certificiate for domain or
# create one certificate with all their subdomains (max 100!)
__generateProxyUrls "$PROXY_ADDRESS" "$PROXY_PORT"
# Above function returns ${proxyServerUrls}
# Clear previous validations
rm -rf /tmp/validation_complete* >/dev/null 2>&1
__processDomainEnvVarsAndGenCerts "$(env | grep 'DOMAIN_')"
__updateProxies "${proxyServerUrls}"

RENEW_INTERVAL=86400 # 1 day
maxFailCount=10 # We will mark this container as unhealthy if we exceed this
failCount=0
__renewCertLoop # This is an endless loop
exit 1 # We dont expect script to reach here.
