#!/bin/bash
# Remove manual record creation from Dockerhub
# Remove the GET key from Dockerhub
# Add ability to create issues on github
# Add changelog
# Make PUT request pretty
# Add logic to check if api requests succeed or fail and log appropriately
# Need logic checks for PUT and POST requests
# Add some logic to PUT request to not run on obvious errors

set -euo pipefail

# Environment
NAME=${DNS_RECORD_NAME}
PUT_KEY=${PUT_KEY}

# Optional environment
: "${TTL:=120}"
: "${PROXIED:=false}"

function get_zone_id() {
    # return Zone ID to outside variable
    echo $(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones?name=$NAME" \
     -H "Authorization: Bearer $PUT_KEY" \
     -H "Content-Type: application/json" |  jq -r '.result[] | .id')
}

# Get the DNS Zone ID and the IP stored on CloudFlare.
function get_dns_record_ip_and_id() {
    # return IP to outside variable
    echo $(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $PUT_KEY" \
    -H "Content-Type: application/json" | jq -r '.result[] | select(.name == "'"$NAME"'" and .type == "A") | .content, .id')
}

#function create_dns_record() {
#    # Create a new DNS record if none exists
#    
#}

# Start script execution
echo -e "\e[93mRunning update-ip.sh script at $(date)\e[0m"

# Get the external IP of the web server.
CURRENT_IP=$(curl -s http://checkip.amazonaws.com)

# Get the DNS zone ID for the domain dynamically
ZONE_ID=$(get_zone_id)

# Get the dns record id and the IP address stored in the A record on CloudFlare dynamically.
IPANDID=$(get_dns_record_ip_and_id)

if [ -z "$IPANDID" ]; then
  # Create the DNS record if none exists
  curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
      -H "Authorization: Bearer $PUT_KEY" \
      -H "Content-Type: application/json" \
      --data '{
       "type": "A",
       "name": "'"$NAME"'",
       "content": "'"$CURRENT_IP"'",
       "ttl": '"$TTL"',
       "proxied": '"$PROXIED"'
      }' | jq

  echo -e "\e[33mDNS record created with IP $CURRENT_IP, response above.\n\e[0m"
else
  # Otherwise check if IP has changed and update if necessary
  echo "Existing DNS record found for $NAME. No action needed."
fi

LAST_IP=$(echo $IPANDID | awk '{print $1}')
DNS_ID=$(echo $IPANDID | awk '{print $2}')

# Compare the current IP with the last known IP and update on cloudflare if it has changed.
if [ "$CURRENT_IP" != "$LAST_IP" ]; then
  echo -e "\e[33mIP has changed from $LAST_IP to $CURRENT_IP.\n\e[0m"
  
  # Add the PUT request to update the IP address on CloudFlare.
  # Currently only supports A records.
  response=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
      -H "Authorization: Bearer $PUT_KEY" \
      -H "Content-Type: application/json" \
      --data '{"type":"A","name":"'"$NAME"'","content":"'"$CURRENT_IP"'","proxied":'"$PROXIED"',"ttl":'"$TTL"'}' | jq)
  
  echo -e "Response:\n$response\n"
  echo -e "\e[33mIP updated to $CURRENT_IP, response above.\n\e[0m"
else
  echo -e "\e[33mIP has not changed, exiting.\n\e[0m"
fi