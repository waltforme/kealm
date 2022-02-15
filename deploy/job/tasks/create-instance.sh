#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 --host-ip <host-ip> [--external-ip <external-ip>]"
    exit
fi

ARGS=$(getopt -a --options h:e: --long "host-ip:,external-ip:" -- "$@")
eval set -- "$ARGS"

while true; do
  case "$1" in
    -h|--host-ip)
      CLUSTER_IP="$2"
      shift 2;;
    -e|--external-ip)
      externalIP="$2"
      shift 2;; 
    --)
      break;;
     *)
      printf "Unknown option %s\n" "$1"
      exit 1;;
  esac
done

${SCRIPT_DIR}/vks/create-vks.sh --host-ip=${CLUSTER_IP} --external-ip=${externalIP}

${SCRIPT_DIR}/ocm/deploy-cluster-manager.sh --host-ip=${CLUSTER_IP} --external-ip=${externalIP}

if [ "$DEPLOY_FLOTTA" == "true" ]; then
  echo "deploying flotta..." 
  ${SCRIPT_DIR}/flotta/deploy-flotta.sh --host-ip=${CLUSTER_IP} --external-ip=${externalIP}
fi
