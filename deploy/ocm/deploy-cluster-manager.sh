#!/bin/bash

PROJECT_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/../.. && pwd )"

source ${PROJECT_HOME}/deploy/vks/config.sh

###############################################################################################
#               Functions
###############################################################################################

deploy_vks_manifests() {
    kubectl --kubeconfig=${VKS_HOME}/admin.conf apply -f ${PROJECT_HOME}/deploy/ocm/vks-manifests
}

deploy_cluster_manager() {
    kubectl apply -n ${VKS_NS} -f ${PROJECT_HOME}/deploy/ocm/host-manifests
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

###########################################################################################
#                   Main   
###########################################################################################

unset KUBECONFIG

deploy_vks_manifests

deploy_cluster_manager

if [ "$USE_KIND" == "true" ]; then 
    CLUSTER_IP=$(get_kind_cluster_ip)
    server=https://${CLUSTER_IP}:${KIND_CLUSTER_NODEPORT}
fi

token=$(get_bootstrap_token)

echo ""
echo "cluster manager has been started! To join clusters run the command (make sure to use the correct <cluster-name>:"
echo ""
echo "clusteradm join --hub-token $token --hub-apiserver $server --cluster-name <cluster-name>"
