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
# Change your target hostname, dns server 2 and 3. 
# Constants
COREDNS_CONFIG="coredns-custom.yaml"
DNS_JOB="dns-lookup-job.yaml"
TARGET_HOSTNAME="example.com"
DNS_SERVER_1="168.63.129.16" # AzureDNS
DNS_SERVER_2="198.51.100.1"
DNS_SERVER_3="203.0.113.1"

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

verify_dns_job() {
    log "Waiting for DNS test job to complete..."
    kubectl wait --for=condition=complete --timeout=60s job/dns-lookup-job
    log "DNS test job completed successfully. Fetching logs..."
    kubectl logs job/dns-lookup-job
}

cleanup() {
    log "Cleaning up resources..."
    kubectl delete configmap coredns-custom -n kube-system || true
    kubectl delete job dns-lookup-job || true
    rm -f $COREDNS_CONFIG $DNS_JOB
}

run_unit_tests() {
    log "Running unit tests..."
    log "Testing CoreDNS ConfigMap creation..."
    apply_coredns_config
    kubectl get configmap coredns-custom -n kube-system &> /dev/null \
        && log "CoreDNS ConfigMap test passed" \
        || (log "CoreDNS ConfigMap test failed"; exit 1)

    log "Testing DNS job creation..."
    create_dns_job
    kubectl get job dns-lookup-job &> /dev/null \
        && log "DNS job creation test passed" \
        || (log "DNS job creation test failed"; exit 1)

    log "Testing CoreDNS logging for target hostname..."
    verify_coredns_logs
}

# Main Script Execution
trap cleanup EXIT

log "Starting script to enhance DNS logging and test configuration with target hostname logging..."
apply_coredns_config
restart_coredns
create_dns_job
verify_dns_job
verify_coredns_logs
#run_unit_tests
log "Script completed successfully."

