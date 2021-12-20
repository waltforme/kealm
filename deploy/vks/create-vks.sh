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
    echo "checking VKS Host node is up..."
    for (( ; ; ))
    do
        echo -n "."
        JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'  && kubectl get nodes -o jsonpath="$JSONPATH" | grep "Ready=True" > /dev/null
        if [ "$?" -eq 0 ]; then
            echo ""
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
    IP=$1
    mkdir -p ${VKS_HOME}/pki
    rm ${VKS_HOME}/*.conf &>/dev/null
    kubeadm init phase certs --cert-dir=${VKS_HOME}/pki \
    --control-plane-endpoint=$1 \
    --apiserver-cert-extra-sans=${VKS_NAME},${VKS_NAME}.${VKS_NS},${VKS_NAME}.${VKS_NS}.svc,${VKS_NAME}.${VKS_NS}.svc.cluster.local  all
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

create_or_update_certs_secret() {
    kubectl delete -n ${VKS_NS} secret k8s-certs &> /dev/null
    kubectl create -n ${VKS_NS} secret generic k8s-certs \
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
        sed "s/{{ .vksNS }}/${VKS_NS}/g" | \
        sed "s/{{ .DBReleaseName }}/${DB_RELEASE_NAME}/g" > ${VKS_HOME}/manifests/kube-apiserver.yaml

    cat ${PROJECT_HOME}/deploy/vks/manifests/kube-apiserver-service.yaml | \
        sed "s/{{ .vksName }}/${VKS_NAME}/g" | \
        sed "s/{{ .securePort }}/${API_SERVER_PORT}/g" | \
        sed "s/{{ .clusterPort }}/${KIND_CLUSTER_NODEPORT}/g" > ${VKS_HOME}/manifests/kube-apiserver-service.yaml

    cat ${PROJECT_HOME}/deploy/vks/manifests/kube-controller-manager.yaml | \
        sed "s/{{ .vksName }}/${VKS_NAME}/g" | \
        sed "s/{{ .securePort }}/${API_SERVER_PORT}/g" > ${VKS_HOME}/manifests/kube-controller-manager.yaml
}

apply_manifests() {
    kubectl apply -n ${VKS_NS} -f ${VKS_HOME}/manifests/kube-apiserver.yaml
    kubectl apply -n ${VKS_NS} -f ${VKS_HOME}/manifests/kube-apiserver-service.yaml
}

update_kubeconfig() {
    IP=$1
    CURRENT_SERVER=$(cat ${VKS_HOME}/admin.conf | grep server: | awk '{print $2}')
    sed "s|${CURRENT_SERVER}|https://${IP}:${KIND_CLUSTER_NODEPORT}|g" ${VKS_HOME}/admin.conf -i""
}

check_vks_up() {
    echo "checking ${VKS_NAME} is up..."
    echo "press CTRL+C to exit"
    for (( ; ; ))
    do
        echo -n "."
        kubectl --kubeconfig=${VKS_HOME}/admin.conf cluster-info &> /dev/null
        if [ "$?" -eq 0 ]; then
            echo ""
            echo "${VKS_NAME} ready!"
            kubectl --kubeconfig=${VKS_HOME}/admin.conf cluster-info
            break
        fi
        sleep 2
    done
}

upload_kubeadm_config() {
    kubeadm --kubeconfig=${VKS_HOME}/admin.conf init phase upload-config kubeadm
    kubectl --kubeconfig=${VKS_HOME}/admin.conf -n kube-system get configmap kubeadm-config \
        -o jsonpath='{.data.ClusterConfiguration}' > ${VKS_HOME}/kubeadm.yaml
}

update_sans() {
    IP=$1
    python3 -c \
    "import yaml;f=open(\"${VKS_HOME}/kubeadm.yaml\",'r');y=yaml.safe_load(f);\
    y['apiServer']['certSANs']=[\"${IP}\",\"${VKS_NAME}\",\"${VKS_NAME}.${VKS_NS}\",\"${VKS_NAME}.${VKS_NS}.svc\",\"${VKS_NAME}.${VKS_NS}.svc.cluster.local\"];\
    y['certificatesDir']=\"${VKS_HOME}/pki\";\
    f.close();f=open(\"${VKS_HOME}/kubeadm.yaml\",'w');yaml.dump(y, f, default_flow_style=False, sort_keys=False)" 

    mkdir -p ${VKS_HOME}/pki/backups
    mv ${VKS_HOME}/pki/apiserver.{crt,key} ${VKS_HOME}/pki/backups
    kubeadm init phase certs apiserver --config ${VKS_HOME}/kubeadm.yaml
}

restart_api_server() {
    kubectl scale deploy -n ${VKS_NS} --replicas=0 kube-apiserver
    kubectl scale deploy -n ${VKS_NS} --replicas=1 kube-apiserver
}

create_cm_secret() {
    CURRENT_SERVER=$(cat ${VKS_HOME}/controller-manager.conf | grep server: | awk '{print $2}')
    sed "s|${CURRENT_SERVER}|https://${VKS_NAME}:${API_SERVER_PORT}|g" ${VKS_HOME}/controller-manager.conf -i""  
    kubectl -n ${VKS_NS} delete secret cm-kubeconfig &>/dev/null
    kubectl -n ${VKS_NS} create secret generic cm-kubeconfig \
        --from-file=${VKS_HOME}/controller-manager.conf 
}

apply_cm_manifests() {
    kubectl apply -n ${VKS_NS} -f ${VKS_HOME}/manifests/kube-controller-manager.yaml
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

create_certs $CLUSTER_IP

create_vks_ns

install_db

DB_PASSWORD=$(get_db_password)

create_or_update_certs_secret

configure_manifests ${DB_PASSWORD}

apply_manifests

update_kubeconfig $CLUSTER_IP

check_vks_up

upload_kubeadm_config

create_cm_secret

apply_cm_manifests