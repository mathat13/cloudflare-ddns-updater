#!/bin/bash
set -euo pipefail

# Environment
NAME=${DNS_RECORD_NAME}
PUT_KEY=${PUT_KEY}

# Optional environment
: "${TTL:=1}"
: "${PROXIED:=false}"
: "${DEBUG:=false}"

# Log colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# Logging functions
log_info()    { echo -e "${YELLOW}[INFO] $*${RESET}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $*${RESET}"; }
log_error()   { echo -e "${RED}[ERROR] $*${RESET}" >&2; }
log_debug()   { if [ "$DEBUG" = "true" ]; then echo -e "${CYAN}[DEBUG] $*${RESET}"; fi }

function get_zone_information() {
    # return Zone ID to outside variable
    response=$(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones?name=$NAME" \
     -H "Authorization: Bearer $PUT_KEY" \
     -H "Content-Type: application/json")
     #check_api_call_success "$response" "Fetch zone information"
     echo "$response"
}

# Return IP and DNS zone ID for the given domain to outside variable
function get_dns_record_information() {
    echo $(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $PUT_KEY" \
    -H "Content-Type: application/json")
}

function create_dns_record() {
  echo $(curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $PUT_KEY" \
    -H "Content-Type: application/json" \
    --data '{
      "type": "A",
      "name": "'"$NAME"'",
      "content": "'"$CURRENT_IP"'",
      "proxied": '"$PROXIED"',
      "ttl": '"$TTL"'
    }'
  )    
}

function update_dns_record() {
  # Add the PUT request to update the IP address on CloudFlare.
  # Currently only supports A records.
  echo $(curl -sS -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
    -H "Authorization: Bearer $PUT_KEY" \
    -H "Content-Type: application/json" \
    --data '{
      "type":"A",
      "name":"'"$NAME"'",
      "content":"'"$CURRENT_IP"'",
      "proxied":'"$PROXIED"',
      "ttl":'"$TTL"'
    }'
  )
}

function check_api_call_success() {

  local api_response="$1"
  local action="$2"  # description of the API call

  if [ "$(echo "$api_response" | jq -r '.success')" != "true" ]; then
    log_error "API call '$action' failed, error message: $(echo "$api_response" | jq -r '.errors[] | .message')\n"
    exit 1
  fi
}

# Check TTL is sane
if [ "$TTL" -ne 1 ] && [ "$TTL" -lt 120 ]; then
  log_error "Invalid TTL: $TTL. Must be 1 (auto) or >= 120, exiting."
  exit 1
fi

# Get the external IP of the web server.
CURRENT_IP=$(curl -s http://checkip.amazonaws.com)

# Check if we successfully fetched the current IP
if [ -z "$CURRENT_IP" ]; then
  log_error "Failed to fetch current IP. Please check connection, exiting\n"
  exit 1
fi

# Get the DNS zone ID for the domain dynamically
ZONE_RESPONSE=$(get_zone_information)
echo "$ZONE_RESPONSE"  # pretty print the full response for debugging
ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r '.result[] | .id')

# exit if zone id is empty
if [ -z "$ZONE_ID" ]; then
  log_error "Failed to fetch domain zone id. Please check if the domain '$NAME' exists and the API token has the necessary permissions, exiting.\n"
  exit 1
fi

# Attempt to grab the IP and DNS record ID from the dns record stored on cloudflare
RECORDS_RESPONSE=$(get_dns_record_information)
check_api_call_success "$RECORDS_RESPONSE" "Fetch DNS record"

# Store the last IP and DNS ID in separate variables
read -r LAST_IP DNS_ID < <(echo "$RECORDS_RESPONSE" | jq -r '.result[]? | select(.name == "'"$NAME"'" and .type == "A") | [.content, .id] | @tsv')

log_info "Checking if a DNS record already exists for $NAME...\n"

# Check if a DNS record exists
if [ -z "$DNS_ID" ] && [ -z "$LAST_IP" ]; then
  log_info "No existing DNS record found for $NAME. Creating one...\n"
  # If so, Create the DNS record
  CREATE_RESPONSE=$(create_dns_record)
  check_api_call_success "$CREATE_RESPONSE" "Create DNS record"

  # Pretty print the JSON response
  PRETTY_CREATE_RESPONSE=$(echo "$CREATE_RESPONSE" | jq)
  log_success "DNS record created with IP: $CURRENT_IP.\n"
  log_debug "Create response:\n$PRETTY_CREATE_RESPONSE\n"

else
  # Otherwise check if IP has changed and update if necessary
  log_info "Existing DNS record found for $NAME. Checking if IP has changed...\n"

  if [ "$CURRENT_IP" != "$LAST_IP" ]; then
    log_info "Record IP has changed from $LAST_IP to $CURRENT_IP.\n"
    # Update the DNS record with the new IP
    UPDATE_RESPONSE=$(update_dns_record)
    check_api_call_success "$UPDATE_RESPONSE" "Update DNS record"

    # Pretty print the JSON response
    PRETTY_UPDATE_RESPONSE=$(echo "$UPDATE_RESPONSE" | jq)
    log_success "Record IP updated to $CURRENT_IP.\n"
    log_debug "Update response:\n$PRETTY_UPDATE_RESPONSE\n"

  else
    log_info "IP has not changed, exiting.\n"
  fi
fi