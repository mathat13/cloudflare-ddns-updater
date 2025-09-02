#!/bin/bash
# Create the record in script and remove record creation from Dockerhub
# Remove the GET key from the script and Dockerhub
# Set up automatic updates with GitHub
# Add default values for PROXIED and TTL
# Upload project to Github


# Environment
NAME=${DNS_RECORD_NAME}
GET_KEY=${GET_KEY}
PUT_KEY=${PUT_KEY}
ZONE_ID=${DNS_ZONE_ID}

# Optional environment
# TTL="${TTL:-120}"
# PROXIED="${PROXIED:-1}"
TTL="120"
PROXIED="true"

# Get the DNS Zone ID and the IP stored on CloudFlare.
function get_dns_ip_and_id() {
    # return IP to outside variable
    echo $(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $PUT_KEY" \
    -H "Content-Type: application/json" | jq -r '.result[] | select(.name == "'"$NAME"'" and .type == "A") | .content, .id')
}

# Update the DNS Record with the selected values.
function update_dns_record() {
    # IP expected.
    local CONTENT=$1

    # Type is hard-coded due to only being able to create an A record for this to work.
    local response=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
        -H "Authorization: Bearer $PUT_KEY" \
        -H "Content-Type: application/json" \
        --data '{"type":"A","name":"'"$NAME"'","content":"'"$CONTENT"'","proxied":'"$PROXIED"',"ttl":'"$TTL"'}' | jq)
    
    echo -e "Response:\n$response\n"
}

# Start script execution
echo -e "\e[93mRunning update-ip.sh script at $(date)\e[0m"

# Get the external IP of the web server.
CURRENT_IP=$(curl -s http://checkip.amazonaws.com)

# Get the dns record id and the IP address stored in the A record on CloudFlare dynamically.
IPANDID=$(get_dns_ip_and_id)

LAST_IP=$(echo $IPANDID | awk '{print $1}')
DNS_ID=$(echo $IPANDID | awk '{print $2}')

# Compare the current IP with the last known IP and update on cloudflare if it has changed.
if [ "$CURRENT_IP" != "$LAST_IP" ]; then
  echo -e "\e[33mIP has changed from $LAST_IP to $CURRENT_IP.\n\e[0m"
  update_dns_record $CURRENT_IP
  echo -e "\e[33mIP updated to $CURRENT_IP, response above.\n\e[0m"
else
  echo -e "\e[33mIP has not changed.\n\e[0m"
fi