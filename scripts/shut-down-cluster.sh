#!/bin/bash -eux

CONTROL_NODE="pi0"
WORKER_NODES=("pi1" "pi2")

wait_a_bit() {
    echo "Waiting for 10 seconds..."
    sleep 10
}

handle_error() {
    echo "Error occurred at line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

echo "==== Starting Kubernetes cluster shutdown procedure ===="

echo "Step 1: Draining worker nodes..."
for node in "${WORKER_NODES[@]}"; do
    echo "Draining node $node..."
    ssh $CONTROL_NODE "kubectl drain $node --ignore-daemonsets --delete-emptydir-data --force"
done

wait_a_bit

echo "Step 1.5: Verifying worker nodes are properly drained..."
for node in "${WORKER_NODES[@]}"; do
    echo "Checking pods on node $node..."
    # Get count of pods (excluding DaemonSets which will still be there)
    pod_count=$(ssh $CONTROL_NODE "kubectl get pods --all-namespaces --field-selector spec.nodeName=$node | grep -v 'kube-system' | grep -v 'DaemonSet' | wc -l")
    
    # Check if there are still pods running or pending (excluding system pods and headers)
    if [[ $pod_count -gt 1 ]]; then
        echo "WARNING: Node $node still has pods running. Showing remaining pods:"
        ssh $CONTROL_NODE "kubectl get pods --all-namespaces --field-selector spec.nodeName=$node"
        read -p "Continue with shutdown anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborting cluster shutdown."
            exit 1
        fi
    else
        echo "Node $node is properly drained (only system pods remaining)."
    fi
done

wait_a_bit

echo "Step 2: Shutting down worker nodes..."
for node in "${WORKER_NODES[@]}"; do
    echo "Shutting down worker node: $node"
    ssh $node 'sudo shutdown -h now'
done

wait_a_bit

echo "Step 3: Draining control node ($CONTROL_NODE)..."
ssh $CONTROL_NODE "kubectl drain $CONTROL_NODE --ignore-daemonsets --delete-emptydir-data --force"

wait_a_bit

# Step 3.5: Verify control node is properly drained
echo "Step 3.5: Verifying control node is properly drained..."
echo "Checking pods on control node $CONTROL_NODE..."
# Get count of pods on the control node (excluding DaemonSets which will still be there)
pod_count=$(ssh $CONTROL_NODE "kubectl get pods --all-namespaces --field-selector spec.nodeName=$CONTROL_NODE | grep -v 'kube-system' | grep -v 'DaemonSet' | wc -l")

# Check if there are still pods running or pending (excluding system pods and headers)
if [[ $pod_count -gt 1 ]]; then
    echo "WARNING: Control node $CONTROL_NODE still has pods running. Showing remaining pods:"
    ssh $CONTROL_NODE "kubectl get pods --all-namespaces --field-selector spec.nodeName=$CONTROL_NODE"
    read -p "Continue with shutdown anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting cluster shutdown."
        exit 1
    fi
else
    echo "Control node $CONTROL_NODE is properly drained (only system pods remaining)."
fi

wait_a_bit

# Step 4: Shut down control plane
echo "Step 4: Shutting down control plane node ($CONTROL_NODE)..."
ssh $CONTROL_NODE 'sudo shutdown -h now'

echo "==== Kubernetes cluster shutdown complete ===="