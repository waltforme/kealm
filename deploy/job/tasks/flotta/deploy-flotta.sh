#!/bin/bash

HOME_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source ${HOME_DIR}/../vks/config.sh

###############################################################################################
#               Functions
###############################################################################################

deploy_vks_manifests() {
    sed -i.bak "s|{{ .namespace }}|${VKS_NS}|g" ${HOME_DIR}/vks-manifests/0000_03_role_binding.yaml
    rm ${HOME_DIR}/vks-manifests/0000_03_role_binding.yaml.bak
    kubectl --kubeconfig=${VKS_HOME}/admin.conf apply -f ${HOME_DIR}/vks-manifests
}

create_tls_secret() {
    cp ${VKS_HOME}/pki/apiserver.crt ${VKS_HOME}/pki/tls.crt
    cp ${VKS_HOME}/pki/apiserver.key ${VKS_HOME}/pki/tls.key
    kubectl -n ${VKS_NS} delete secret webhook-server-cert &>/dev/null
    kubectl -n ${VKS_NS} create secret generic webhook-server-cert \
        --from-file=${VKS_HOME}/pki/ca.crt \
        --from-file=${VKS_HOME}/pki/tls.crt \
        --from-file=${VKS_HOME}/pki/tls.key
}

deploy_flotta_manager() {
    kubectl apply -n ${VKS_NS} -f ${HOME_DIR}/host-manifests
    kubectl -n ${VKS_NS} wait --for=condition=available --timeout=600s deployment/flotta-operator-controller-manager
}

###########################################################################################
#                   Main   
###########################################################################################

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

deploy_vks_manifests

create_tls_secret

deploy_flotta_manager

if [ ! -z "$externalIP" ]; then
    echo "External IP $externalIP has been provided, using for join command generation"
    hubApiserver=https://$externalIP:${FLOTTA_NODEPORT}
else
    hubApiserver=https://${CLUSTER_IP}:${FLOTTA_NODEPORT}
fi

joincmd="join --hub-apiserver ${hubApiserver}"

echo ""
echo "flotta manager has been started! To join edge devices run the command:"
echo ""
echo "$joincmd"

