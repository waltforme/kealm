#!/bin/bash

PROJECT_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/../.. && pwd )"

USE_KIND="${USE_KIND:-true}"

VKS_NAME=vks
VKS_HOME=${PROJECT_HOME}/.${VKS_NAME}
DB_RELEASE_NAME=mypsql
VKS_NS=${VKS_NAME}-system
KIND_CLUSTER_NAME=vkshost
KIND_CLUSTER_NODEPORT=31433
API_SERVER_PORT=7443

###############################################################################################
#               Functions
###############################################################################################

check_kind_cluster_exists() {
    kind get kubeconfig --name ${KIND_CLUSTER_NAME} &> /dev/null
    if [ "$?" -eq 0 ]; then
        echo "true"
    else
        echo "false" 
    fi
}

create_kind_cluster() {
    mkdir -p ${VKS_HOME}/kind
    cat ${PROJECT_HOME}/deploy/vks/manifests/kind-cluster.yaml | \
        sed "s/{{ .clusterName }}/${KIND_CLUSTER_NAME}/g" | \
        sed "s/{{ .clusterPort }}/${KIND_CLUSTER_NODEPORT}/g" > ${VKS_HOME}/kind/kind-cluster.yaml
    kind create cluster --config=${VKS_HOME}/kind/kind-cluster.yaml --wait 5m
    check_node_ready
}

check_node_ready() {
    for (( ; ; ))
    do
        JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'  && kubectl get nodes -o jsonpath="$JSONPATH" | grep "Ready=True" > /dev/null
        if [ "$?" -eq 0 ]; then
            echo "Node ready!"
            break
        fi
        sleep 2
    done
}

get_kind_cluster_ip() {
    docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${KIND_CLUSTER_NAME}-control-plane
}

create_certs() {
    mkdir -p ${VKS_HOME}/pki
    kubeadm init phase certs --cert-dir=${VKS_HOME}/pki all
    kubeadm init phase kubeconfig --cert-dir=${VKS_HOME}/pki --kubeconfig-dir=${VKS_HOME} admin
    kubeadm init phase kubeconfig --cert-dir=${VKS_HOME}/pki --kubeconfig-dir=${VKS_HOME} controller-manager
}

create_vks_ns() {
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: ${VKS_NS}
  name: ${VKS_NS}
EOF
}

install_db() {
    helm get --namespace ${VKS_NS} all ${DB_RELEASE_NAME} &> /dev/null
    if [ "$?" -eq 0 ]; then
        return
    fi    
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm install --namespace ${VKS_NS} ${DB_RELEASE_NAME} bitnami/postgresql
}

get_db_password() {
    DB_PASSWORD=$(kubectl get secret --namespace ${VKS_NS} ${DB_RELEASE_NAME}-postgresql \
        -o jsonpath="{.data.postgresql-password}" | base64 --decode)
    echo ${DB_PASSWORD}   
}

create_certs_secret() {
    kubectl delete secret k8s-certs &> /dev/null
    kubectl create secret generic k8s-certs \
    --from-file=${VKS_HOME}/pki/ca.crt \
    --from-file=${VKS_HOME}/pki/ca.key \
    --from-file=${VKS_HOME}/pki/apiserver-kubelet-client.crt \
    --from-file=${VKS_HOME}/pki/apiserver-kubelet-client.key \
    --from-file=${VKS_HOME}/pki/front-proxy-client.crt \
    --from-file=${VKS_HOME}/pki/front-proxy-client.key \
    --from-file=${VKS_HOME}/pki/front-proxy-ca.crt \
    --from-file=${VKS_HOME}/pki/sa.pub \
    --from-file=${VKS_HOME}/pki/sa.key \
    --from-file=${VKS_HOME}/pki/apiserver.crt \
    --from-file=${VKS_HOME}/pki/apiserver.key
}  

configure_manifests() {
    DB_PASSWORD=$1
    mkdir -p ${VKS_HOME}/manifests
    cat ${PROJECT_HOME}/deploy/vks/manifests/kube-apiserver.yaml | \
        sed "s/{{ .DBPassword }}/${DB_PASSWORD}/g" | \
        sed "s/{{ .securePort }}/${API_SERVER_PORT}/g" | \
        sed "s/{{ .DBReleaseName }}/${DB_RELEASE_NAME}/g" > ${VKS_HOME}/manifests/kube-apiserver.yaml

    cat ${PROJECT_HOME}/deploy/vks/manifests/kube-apiserver-service.yaml | \
        sed "s/{{ .vksName }}/${VKS_NAME}/g" | \
        sed "s/{{ .securePort }}/${API_SERVER_PORT}/g" | \
        sed "s/{{ .clusterPort }}/${KIND_CLUSTER_NODEPORT}/g" > ${VKS_HOME}/manifests/kube-apiserver-service.yaml  
}

apply_manifests() {
    kubectl apply -n ${VKS_NS} -f ${VKS_HOME}/manifests/kube-apiserver.yaml
    kubectl apply -n ${VKS_NS} -f ${VKS_HOME}/manifests/kube-apiserver-service.yaml
}

###########################################################################################
#                   Main   
###########################################################################################

if [ "$USE_KIND" == "true" ]; then 
    kind_cluster_exists=$(check_kind_cluster_exists)
    if [ "$kind_cluster_exists" == "false" ]; then
        create_kind_cluster
    fi
    CLUSTER_IP=$(get_kind_cluster_ip)
fi    

create_certs

create_vks_ns

install_db

DB_PASSWORD=$(get_db_password)

create_certs_secret

configure_manifests ${DB_PASSWORD}

apply_manifests

