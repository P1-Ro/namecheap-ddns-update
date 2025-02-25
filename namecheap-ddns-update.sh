#!/bin/bash
GLOBIGNORE="*"
# for a domain you own hosted at namecheap, register one or more subdomains
# to an IP address in namecheaps dynamicdns system

if [ -r $(dirname "$0")/.env ]; then
  echo "Sourcing .env file at the same dir"
  source $(dirname "$0")/.env
elif [ -r ~/.namecheap-ddns-update ]; then
  echo "Sourcing user ($USER) .namecheap-ddns-update file"
  source ~/.namecheap-ddns-update
fi

echo ""

##############################################################################
# Update the domain subdomains
##############################################################################
update() {
  local LOCAL_DOMAIN=$1
  local LOCAL_PWD=$2
  local LOCAL_SUBDOMAINS=$3
  echo "Updating domain: $LOCAL_DOMAIN, with subdomains: $LOCAL_SUBDOMAINS"
  # Create the static URL
  BASE_URL="https://dynamicdns.park-your-domain.com/update?domain=$LOCAL_DOMAIN&password=$LOCAL_PWD&ip=$IP"
  # Set the IP address for each raw_domain, subdomain combination
  # Only redefine IFS in the while loop
  while IFS=',' read -ra SUBDOMAIN_ARRAY; do
    for raw_subdomain in "${SUBDOMAIN_ARRAY[@]}"; do
      SUBDOMAIN="$(echo -e $raw_subdomain | tr -d '[[:space:]]')"
      echo "Registering subdomain: $SUBDOMAIN.$LOCAL_DOMAIN, to IP address: $IP"
      URL="$BASE_URL&host=$SUBDOMAIN"
      RESP="$(curl --silent --connect-timeout 10 $URL)"
      error_msg="$(echo -e $RESP | gawk '{ match($0, /<ErrCount>(.*)<\/ErrCount>.+<Err1>(.*)<\/Err1>/, arr); if (arr[1] > 0 ) print arr[2] }')"
      if [ "$error_msg" ]; then
        echo "ERROR : $error_msg" 1>&2;
        if [ "$EXIT_ON_ERROR" = true ]; then
          exit 1
        fi
      else
        new_ip="$(echo -e $RESP | gawk '{ match($0, /<IP>(.*)<\/IP>/, arr); if (arr[1] != "" ) print arr[1] }')"
        echo "$SUBDOMAIN.$LOCAL_DOMAIN IP address updated to: $new_ip"
      fi
    done
  done <<< "$LOCAL_SUBDOMAINS"
  echo ""
 }

# Usage info
show_help() {
cat << EOF

Usage: ${0##*/} [-h] [-e] [-d DOMAIN] [-s SUBDOMAINS] [-m MULTI_DOMAINS] [-i IP] [-t INTERVAL]

Update the IP address of one or more domains subdomains that you own at
namecheap.com. This can only update an existing A record, it cannot create
a new A record. Use namecheap's advanced DNS settings for your domain to
create A records.

For details on how this works see:
https://www.namecheap.com/support/knowledgebase/article.aspx/29/11/how-do-i-use-a-browser-to-dynamically-update-the-hosts-ip

The args d, s, m, i and t have corresponding ENV options. The Dynamic DNS
Password has to be set for each domain with the NC_DDNS_PASS environment
variable. If there is one domain being updated, then the format of the
NC_DNS_PASS value is the domain password. If you want to update multiple
domains, then the value is a comma separated list of domain/password pairs.
Example: NC_DNS_PASS=example.com=1a2s3d4f5g,example2.com=5g6h7j8k9l

You could also create an environment file in the same directory as the script,
called .env, or in directory of the user running this script, called
.namecheap-ddns-update. The .env file is sourced first if found, if it does
not exist, then .namecheap-ddns-update sourced if found.

    -h                display this help and exit
    -e                exit if any call to update a subdomains IP address fails
    -d DOMAIN         the domain that has one or more SUBDOMAINS (A records)
                      to update. DOMAIN/SUBDOMAINS can be used at the same
                      time as MULTI_DOMAINS to update multiple domains
    -s SUBDOMAINS     comma separated list of subdomains (A records) of DOMAIN
                      to update. DOMAIN/SUBDOMAINS can be used at the same
                      time as MULTI_DOMAINS to update multiple domains
    -m MULTI_DOMAINS  other domains to combine with subdomains (A records). It
                      can be specified multiple times on the command line,
                      at the same time specified as the environment variable
                      MULTI_DOMAINS. The format for the command line argument
                      is: -m example.com=abc,xyz -m example2.com=def,ghi. The
                      format for the environment variable is:
                      MULTI_DOMAINS=example.com=abc,xyz:example2.com=def,ghi
                      Each domain/subdomains pair is separated by a colon (:)
    -i IP             IP address to set the subdomain(s) to. If blank namecheap
                      will use the callers public IP address.
    -t INTERVAL       set up a interval at which to run this. Uses bash sleep
                      format e.g. NUMBER[SUFFIX] where SUFFIX can be, s for
                      seconds (default), m for minutes, h for hours, d for days

EOF
}

EXIT_ON_ERROR=false

OPTIND=1 # Reset is necessary if getopts was used previously in the script.  It is a good idea to make this local in a function.
while getopts "hd:s:m:i:t:e" opt; do
  case "$opt" in
    h)
        show_help
        exit 0
        ;;
    d)  DOMAIN=$OPTARG
        ;;
    s)  SUBDOMAINS=$OPTARG
        ;;
    m)  MULTI_DOMAINS_ARR+=("$OPTARG")
        ;;
    i)  IP=$OPTARG
        ;;
    t)  INTERVAL=$OPTARG
        ;;
    e)  EXIT_ON_ERROR=true
        ;;
    *)
        show_help >&2
        exit 1
        ;;
  esac
done
shift "$((OPTIND-1))" # Shift off the options and optional --.

##############################################################################
# Process the environment variable and script arguments
##############################################################################
declare -A DOMAIN_PWDS
declare -A DOMAIN_SUBDOMAINS

##############################################################################
# Check and set the password
# For a single domain, the NC_DDNS_PASS is a single value. When setting
# multiple domains, the NC_DDNC_PASS is a comma separated list of key/value
# pairs of the form 'domain=pass' e.g. example.com=123456789
##############################################################################
: "${NC_DDNS_PASS:?Need to set the Dynamic DNS Password}"
if [[ $NC_DDNS_PASS == *"="* ]]; then
  DOMAIN_PWDS_ARR=(${NC_DDNS_PASS//[=,]/ })
  for (( i=0; i<${#DOMAIN_PWDS_ARR[@]}; i+=2 )); do
    DOMAIN_PWDS[${DOMAIN_PWDS_ARR[$i]}]=${DOMAIN_PWDS_ARR[$i+1]}
  done
else
  DOMAIN_PWDS[$DOMAIN]=$NC_DDNS_PASS
fi

##############################################################################
# Check DOMAIN and SUBDOMAINS env or argument, and put the values into the
# DOMAIN_SUBDOMAINS associative array.
# These can only be set once, either as environment variables or via arguments
# to this script
##############################################################################
if [[ ! -z "$DOMAIN" ]]; then
  DOMAIN_SUBDOMAINS[$DOMAIN]=$SUBDOMAINS
fi

# Check if the MULTI_DOMAINS environment variable was set
if [[ ! -z "$MULTI_DOMAINS" ]]; then
  DOMAIN_SUBDOMAINS_ARR=(${MULTI_DOMAINS//[=:]/ })
  for (( i=0; i<${#DOMAIN_SUBDOMAINS_ARR[@]}; i+=2 )); do
    DOMAIN_SUBDOMAINS[${DOMAIN_SUBDOMAINS_ARR[$i]}]=${DOMAIN_SUBDOMAINS_ARR[$i+1]}
  done
fi

##############################################################################
# Check MULTI_DOMAINS_ARR arguments, and put the values into the
# DOMAIN_SUBDOMAINS associative array.
# The argument can be specified multiple times, each one is put into the
# MULTI_DOMAINS_ARR array. Each array entry is of the form example.com=abc,zyx
##############################################################################
if [[ ! -z "$MULTI_DOMAINS_ARR" ]]; then
  for multi_domain in "${MULTI_DOMAINS_ARR[@]}"; do
    DOMAIN_SUBDOMAINS_ARR=(${multi_domain//[=]/ })
    for (( i=0; i<${#DOMAIN_SUBDOMAINS_ARR[@]}; i+=2 )); do
      DOMAIN_SUBDOMAINS[${DOMAIN_SUBDOMAINS_ARR[$i]}]=${DOMAIN_SUBDOMAINS_ARR[$i+1]}
    done
  done
fi

# Run the update, either one time or repeat on an interval
if [ "$INTERVAL" ]; then
  # Run in a loop every inteval
  while [ : ]; do
    for domain in "${!DOMAIN_PWDS[@]}"; do
      update $domain ${DOMAIN_PWDS[$domain]} ${DOMAIN_SUBDOMAINS[$domain]}
    done
    sleep $INTERVAL
  done
else
  # Run once and exit
  for domain in "${!DOMAIN_PWDS[@]}"; do
    update $domain ${DOMAIN_PWDS[$domain]} ${DOMAIN_SUBDOMAINS[$domain]}
  done
fi
