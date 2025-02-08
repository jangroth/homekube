#!/bin/bash

# Define the IP addresses of the machines
machines=(
    "192.168.86.220"
    "192.168.86.221"
    "192.168.86.222"
)

# Loop through each machine and shut it down
for ip in "${machines[@]}"; do
    echo "Shutting down machine with IP: $ip"
    ssh $ip 'sudo shutdown -h now'
done

echo "All machines have been shut down."