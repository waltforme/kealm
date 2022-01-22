#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 --name <virtual instance name> --host-ip <host-ip> [--external-ip <external-ip>]"
    exit
fi

ARGS=$(getopt -a --options n:h:e: --long "name:,host-ip:,external-ip:" -- "$@")
eval set -- "$ARGS"

while true; do
  case "$1" in
    -h|--host-ip)
      hostIP="$2"
      shift 2;;
    -e|--external-ip)
      externalIP="$2"
      shift 2;;
    -n|--name)
      name="$2"
      shift 2;;   
    --)
      break;;
     *)
      printf "Unknown option %s\n" "$1"
      exit 1;;
  esac
done

if [ "$name" != "vks1" ] && [ "$name" != "vks2" ] && [ "$name" != "vks3" ]; then
  echo "name must be one of {'vks1','vks2','vks3'}"
  exit -127
fi 

kubectl apply -f ${SCRIPT_DIR}/job/manifests
sed "s/{{ .vksName }}/${name}/g; s/{{ .hostIP }}/${hostIP}/g; s/{{ .externalIP }}/${externalIP}/g" \
	${SCRIPT_DIR}/job/templates/vksjob.yaml | kubectl apply -f -
