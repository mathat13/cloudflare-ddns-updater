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
log_debug()   { if [ "$DEBUG" = "true" ]; then echo -e "${CYAN}[DEBUG] $*${RESET}" >&2; fi }

function get_zone_information() {
  # return Zone ID to outside variable
  response=$(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones?name=$NAME" \
   -H "Authorization: Bearer $PUT_KEY" \
   -H "Content-Type: application/json")
  check_api_call_success "$response" "Fetch zone information"
  echo "$response"
}

# Return IP and DNS zone ID for the given domain to outside variable
function get_dns_record_information() {
  response=$(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $PUT_KEY" \
  -H "Content-Type: application/json")
  check_api_call_success "$response" "Fetch record information"
  echo "$response"
}

function create_dns_record() {
  response=$(curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
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
  check_api_call_success "$response" "Create record"
  echo "$response"  
}

function update_dns_record() {
  # Add the PUT request to update the IP address on CloudFlare.
  # Currently only supports A records.
  response=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
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
  check_api_call_success "$response" "Update record"
  echo "$response"
}

function check_api_call_success() {

  local api_response="$1"
  local action="$2"  # description of the API call

  log_debug "$action response:\n$(echo "$api_response" | jq)\n"

  if [ "$(echo "$api_response" | jq -r '.success')" != "true" ]; then
    log_error "API call '$action' failed, error message: $(echo "$api_response" | jq -r '.errors[] | .message'). Exiting.\n"
    exit 1
  fi
}

log_debug "Confirming TTL"
# Check TTL is sane
if [ "$TTL" -ne 1 ] && [ "$TTL" -lt 120 ]; then
  log_error "Invalid TTL: $TTL. Must be 1 (auto) or >= 120, exiting."
  exit 1
fi
log_debug "TTL confirmed"

# Get the external IP of the web server.
log_debug "Attempting to fetch current external IP from checkip.amazonaws.com\n"
CURRENT_IP=$(curl -s http://checkip.amazonaws.com)
log_debug "Fetched current IP: $CURRENT_IP\n"

# Check if we successfully fetched the current IP
if [ -z "$CURRENT_IP" ]; then
  log_error "Failed to fetch current IP. Please check connection, exiting.\n"
  exit 1
fi

# Get the DNS zone ID for the domain dynamically
log_debug "Fetching zone information for domain: $NAME\n"
ZONE_RESPONSE=$(get_zone_information)

log_debug "Extracting zone ID from response...\n"
ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r '.result[] | .id')
log_debug "Fetched zone ID: $ZONE_ID\n"

# exit if zone id is empty
if [ -z "$ZONE_ID" ]; then
  log_error "Failed to fetch domain zone ID. Please check if the domain '$NAME' exists and the API token has the necessary permissions, exiting.\n"
  exit 1
fi

# Attempt to grab the IP and DNS record ID from the dns record stored on cloudflare
log_debug "Fetching DNS record information for $NAME\n"
RECORDS_RESPONSE=$(get_dns_record_information)

# Store the last IP and DNS ID in separate variables
log_debug "Attempting to extract last IP and DNS ID from response...\n"

# Extract last IP and DNS ID if they exist, otherwise set to empty
record_line=$(echo "$RECORDS_RESPONSE" | jq -r '.result[]? | select(.name == "'"$NAME"'" and .type == "A") | [.content, .id] | @tsv')
if [ -n "$record_line" ]; then
  read -r LAST_IP DNS_ID <<< "$record_line"
  log_debug "Fetched last IP: $LAST_IP, DNS ID: $DNS_ID\n"
else
  LAST_IP=""
  DNS_ID=""
fi

log_info "Checking if a DNS record already exists for $NAME...\n"

# Check if a DNS record exists
if [ -z "$DNS_ID" ] && [ -z "$LAST_IP" ]; then
  log_info "No existing DNS record found for $NAME. Attempting to create one...\n"
  # If so, Create the DNS record
  log_debug "Creating DNS record with IP: $CURRENT_IP\n"
  CREATE_RESPONSE=$(create_dns_record)

  log_success "DNS record created with IP: $CURRENT_IP.\n"

else
  # Otherwise check if IP has changed and update if necessary
  log_info "Existing DNS record found for $NAME. Checking if IP has changed...\n"

  if [ "$CURRENT_IP" != "$LAST_IP" ]; then
    log_info "Record IP has changed from $LAST_IP to $CURRENT_IP, attempting to update record...\n"
    # Update the DNS record with the new IP
    log_debug "Updating DNS record ID: $DNS_ID with new IP: $CURRENT_IP\n"
    UPDATE_RESPONSE=$(update_dns_record)

    log_success "Record IP updated to $CURRENT_IP.\n"

  else
    log_info "IP has not changed, exiting.\n"
  fi
fi