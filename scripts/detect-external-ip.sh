#!/bin/bash -eu

# Define IP services in order of preference
IP_SERVICES=(
  "https://api.ipify.org"
  "https://ifconfig.me"
  "https://checkip.amazonaws.com"
  "https://icanhazip.com"
)

# Function to get IP from a service
get_ip() {
  local service=$1
  curl -s --connect-timeout 5 "$service"
}

# Try each service until one works
for service in "${IP_SERVICES[@]}"; do
  IP=$(get_ip "$service")
  if [[ -n "$IP" && "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$IP - "$(date)" - "$service
    exit 0
  fi
done

# If we get here, all services failed
echo "Error: Could not detect outbound IP address" >&2
exit 1