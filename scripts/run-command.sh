#!/bin/bash -eu

if [ $# -lt 2 ]; then
    echo "Usage: $0 <command> <hostname> [hostname...]"
    echo "Example: $0 'ls -la ~' pi0"
    echo "Example: $0 'ls -la ~' pi0 pi1 pi2"
    exit 1
fi

COMMAND=$1
shift

for HOST in "$@"; do
    echo "=== Executing on $HOST ==="
    ssh $HOST "$COMMAND"
    echo
done

# ./scripts/run-command.sh 'vcgencmd measure_temp' pi0 pi1 pi2
# ./scripts/run-command.sh 'reboot now' pi0 pi1 pi2