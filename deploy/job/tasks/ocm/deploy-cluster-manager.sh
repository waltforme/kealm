#!/bin/bash

HOME_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source ${HOME_DIR}/../vks/config.sh

###############################################################################################
#               Functions
###############################################################################################

deploy_vks_manifests() {
    kubectl --kubeconfig=${VKS_HOME}/admin.conf apply -f ${HOME_DIR}/vks-manifests
}

deploy_cluster_manager() {
    kubectl apply -n ${VKS_NS} -f ${HOME_DIR}/host-manifests
    kubectl -n ${VKS_NS} wait --for=condition=available --timeout=600s deployment/cluster-manager-registration-controller
}

get_kind_cluster_ip() {
    docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${KIND_CLUSTER_NAME}-control-plane
}

get_bootstrap_token() {
   secret_name=$(kubectl --kubeconfig=${VKS_HOME}/admin.conf get sa -n open-cluster-management cluster-bootstrap -o json | jq -r '.secrets[0].name')
   token=$(kubectl --kubeconfig=${VKS_HOME}/admin.conf get secret -n open-cluster-management ${secret_name} -o json | jq -r '.data.token' | base64 -d)
   echo $token
}

create_joincmd_cm() {
    joincmd=$1
    echo ${joincmd} > /tmp/join-cmd
    kubectl create -n ${VKS_NS} configmap join-command --from-file=/tmp/join-cmd
}

check_is_ocp() {
  kubectl get routes.route.openshift.io &> /dev/null
  if [ "$?" -eq 0 ]; then
    echo "true"
  else
    echo "false"
  fi    
}

get_ocp_route_host() {
  kubectl get route ${VKS_NAME} -n ${VKS_NS} -o jsonpath='{.spec.host}'
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

deploy_cluster_manager

if [ ! -z "$externalIP" ]; then
    echo "External IP $externalIP has been provided, using for join command generation"
    SERVER_IP=$externalIP
else
    SERVER_IP=${CLUSTER_IP}
fi

is_ocp=$(check_is_ocp)
if [ "$is_ocp" == "true" ]; then
    SERVER_IP=$(get_ocp_route_host)
    hubApiserver=https://${SERVER_IP}
else
    hubApiserver=https://${SERVER_IP}:${KIND_CLUSTER_NODEPORT}
fi   

token=$(get_bootstrap_token)

joincmd="clusteradm join --hub-token ${token} --hub-apiserver ${hubApiserver} --cluster-name <cluster-name>"

create_joincmd_cm "$joincmd"

echo ""
echo "cluster manager has been started! To join clusters run the command (make sure to use the correct <cluster-name>:"
echo ""
echo "$joincmd"
echo ""
echo "join command available in join-command config map"
