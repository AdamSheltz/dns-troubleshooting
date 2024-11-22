#!/bin/bash
# Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment. 
# THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, 
# INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
# We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the 
# object code form of the Sample Code, provided that. You agree: (i) to not use Our name, logo, or trademarks to market Your 
# software product in which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software product in 
# which the Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against
# any claims or lawsuits, including attorneysΓÇÖ fees, that arise or result from the use or distribution of the Sample Code



set -euo pipefail

# Script for managing CoreDNS logging and DNS test jobs in a Kubernetes cluster.
#
# Usage:
# 1. Default behavior (enable CoreDNS logging and run DNS job):
#    ./script.sh
#
# 2. Disable CoreDNS logging:
#    ./script.sh --disable-coredns-logging
#
# 3. Disable DNS job:
#    ./script.sh --disable-dns-job
#
# 4. Disable both CoreDNS logging and DNS job:
#    ./script.sh --disable-coredns-logging --disable-dns-job
#
# Description:
# - This script can optionally enable or disable enhanced logging in CoreDNS pods.
# - It can also create a test job to verify DNS resolution and remove it after execution.

# Constants
COREDNS_CONFIG="coredns-custom.yaml"
DNS_JOB="dns-lookup-job.yaml"
TARGET_HOSTNAME="example.com" # Edit with a hostname to query. We should see the IP if everything is working.
DNS_SERVER_1="168.63.129.16" # AzureDNS
DNS_SERVER_2="198.51.100.1" # Edit by adding your DNS Server
DNS_SERVER_3="203.0.113.1"  # Edit by adding your DNS Server

# Functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

apply_coredns_config() {
    log "Creating CoreDNS custom ConfigMap with DNS query logging..."
    cat <<EOF > $COREDNS_CONFIG
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  log.override: |
        log
        errors
        cache 30
EOF
    kubectl apply -f $COREDNS_CONFIG
}

remove_coredns_config() {
    log "Removing CoreDNS custom ConfigMap..."
    kubectl delete configmap coredns-custom -n kube-system || true
}

restart_coredns() {
    log "Restarting CoreDNS to apply changes..."
    kubectl -n kube-system rollout restart deployment coredns
}

verify_coredns_logs() {
    log "Verifying CoreDNS logs..."
    if kubectl logs --namespace kube-system -l k8s-app=kube-dns | grep -q "$TARGET_HOSTNAME"; then
        log "Target hostname $TARGET_HOSTNAME found in CoreDNS logs"
    else
        log "Target hostname $TARGET_HOSTNAME NOT found in CoreDNS logs"
        exit 1
    fi
}

create_dns_job() {
    log "Creating DNS test job..."
    cat <<EOF > $DNS_JOB
apiVersion: batch/v1
kind: Job
metadata:
  name: dns-lookup-job
  labels:
    purpose: dns-lookup
spec:
  template:
    metadata:
      labels:
        purpose: dns-lookup
    spec:
      containers:
      - name: dns-lookup-container
        image: appropriate/curl
        command: ["/bin/sh"]
        args:
        - -c
        - >
          echo "Current /etc/resolv.conf:"; 
          cat /etc/resolv.conf; 
          echo "Querying hostname $TARGET_HOSTNAME against configured DNS servers:"; 
          for DNS_SERVER in $DNS_SERVER_1 $DNS_SERVER_2 $DNS_SERVER_3; do 
            echo "Querying DNS server: \$DNS_SERVER"; 
            nslookup $TARGET_HOSTNAME \$DNS_SERVER || dig @\$DNS_SERVER +short $TARGET_HOSTNAME; 
          done;
        env:
        - name: TARGET_HOSTNAME
          value: "$TARGET_HOSTNAME"
        - name: DNS_SERVER_1
          value: "$DNS_SERVER_1"
        - name: DNS_SERVER_2
          value: "$DNS_SERVER_2"
        - name: DNS_SERVER_3
          value: "$DNS_SERVER_3"
      restartPolicy: Never
  backoffLimit: 3
EOF
    kubectl apply -f $DNS_JOB
}

remove_dns_job() {
    log "Removing DNS test job..."
    kubectl delete job dns-lookup-job || true
}

verify_dns_job() {
    log "Waiting for DNS test job to complete..."
    kubectl wait --for=condition=complete --timeout=60s job/dns-lookup-job
    log "DNS test job completed successfully. Fetching logs..."
    kubectl logs job/dns-lookup-job
}

cleanup() {
    log "Cleaning up resources..."
    remove_coredns_config
    remove_dns_job
    rm -f $COREDNS_CONFIG $DNS_JOB
}

# Main Script Execution
trap cleanup EXIT

enable_coredns_logging=true
enable_dns_job=true

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --disable-coredns-logging) enable_coredns_logging=false ;;
        --disable-dns-job) enable_dns_job=false ;;
        *) log "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

log "Starting script with options: CoreDNS logging=${enable_coredns_logging}, DNS job=${enable_dns_job}"

if $enable_coredns_logging; then
    apply_coredns_config
    restart_coredns
else
    log "CoreDNS logging is disabled."
    remove_coredns_config
fi

if $enable_dns_job; then
    create_dns_job
    verify_dns_job
else
    log "DNS test job is disabled."
    remove_dns_job
fi

if $enable_coredns_logging; then
    verify_coredns_logs
fi

log "Script completed successfully."
