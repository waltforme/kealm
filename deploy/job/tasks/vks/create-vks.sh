#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source ${SCRIPT_DIR}/config.sh

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
    cat ${SCRIPT_DIR}/manifests/kind-cluster.yaml | \
        sed "s/{{ .clusterName }}/${KIND_CLUSTER_NAME}/g; \
        s/{{ .clusterPort }}/${KIND_CLUSTER_NODEPORT}/g" > ${VKS_HOME}/kind/kind-cluster.yaml
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

dumpIpForInterface()
{
  IT=$(ifconfig "$1") 
  if [[ "$IT" != *"status: active"* ]]; then
    return
  fi
  if [[ "$IT" != *" broadcast "* ]]; then
    return
  fi
  echo "$IT" | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}'
}

get_host_ip()
{
  DEFAULT_ROUTE=$(route -n get 0.0.0.0 2>/dev/null | awk '/interface: / {print $2}')
  if [ -n "$DEFAULT_ROUTE" ]; then
    dumpIpForInterface "$DEFAULT_ROUTE"
  else
    for i in $(ifconfig -s | awk '{print $1}' | awk '{if(NR>1)print}')
    do 
      if [[ $i != *"vboxnet"* ]]; then
        dumpIpForInterface "$i"
      fi
    done
  fi
}

create_certs() {
    IP=$1
    if [ -z "$2" ]; then
        EXTERNAL_IP=""
    else    
        EXTERNAL_IP=${2},
    fi
    echo "creating certs for IP=${IP} and external IP=${EXTERNAL_IP}"
    mkdir -p ${VKS_HOME}/pki
    rm ${VKS_HOME}/*.conf &>/dev/null
    kubeadm init phase certs --cert-dir=${VKS_HOME}/pki \
    --control-plane-endpoint=$IP \
    --apiserver-cert-extra-sans=${EXTERNAL_IP}${VKS_NAME},${VKS_NAME}.${VKS_NS},${VKS_NAME}.${VKS_NS}.svc,${VKS_NAME}.${VKS_NS}.svc.cluster.local  all 2>/dev/null
    kubeadm init phase kubeconfig --cert-dir=${VKS_HOME}/pki --kubeconfig-dir=${VKS_HOME} admin 2>/dev/null
    kubeadm init phase kubeconfig --cert-dir=${VKS_HOME}/pki --kubeconfig-dir=${VKS_HOME} controller-manager 2>/dev/null
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

create_vksdb_ns() {
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: ${VKSDB_NS}
  name: ${VKSDB_NS}
EOF
}

install_db() {
    helm get --namespace ${VKSDB_NS} all ${DB_RELEASE_NAME} &> /dev/null
    if [ "$?" -eq 0 ]; then
        return
    fi    
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update bitnami
    helm install --namespace ${VKSDB_NS} ${DB_RELEASE_NAME} bitnami/postgresql --version ${POSTGRES_CHART_VERSION} -f ${SCRIPT_DIR}/manifests/postgres-config.yaml
}

get_db_password() {
    DB_PASSWORD=$(kubectl get secret --namespace ${VKSDB_NS} ${DB_RELEASE_NAME}-postgresql \
        -o jsonpath="{.data.postgres-password}" | base64 --decode)
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
    cat ${SCRIPT_DIR}/manifests/kube-apiserver.yaml | \
        sed "s/{{ .DBPassword }}/${DB_PASSWORD}/g; \
        s/{{ .securePort }}/${API_SERVER_PORT}/g;  \
        s/{{ .vksNS }}/${VKS_NS}/g; \
        s/{{ .vksDbNS }}/${VKSDB_NS}/g; \
        s/{{ .vksName }}/${VKS_NAME}/g; \
        s/{{ .DBReleaseName }}/${DB_RELEASE_NAME}/g" > ${VKS_HOME}/manifests/kube-apiserver.yaml

    cat ${SCRIPT_DIR}/manifests/kube-apiserver-service.yaml | \
        sed "s/{{ .vksName }}/${VKS_NAME}/g;  \
        s/{{ .securePort }}/${API_SERVER_PORT}/g; \
        s/{{ .clusterPort }}/${KIND_CLUSTER_NODEPORT}/g" > ${VKS_HOME}/manifests/kube-apiserver-service.yaml

    cat ${SCRIPT_DIR}/manifests/kube-controller-manager.yaml | \
        sed "s/{{ .vksName }}/${VKS_NAME}/g; \
        s/{{ .securePort }}/${API_SERVER_PORT}/g" > ${VKS_HOME}/manifests/kube-controller-manager.yaml
}

apply_manifests() {
    kubectl apply -n ${VKS_NS} -f ${VKS_HOME}/manifests/kube-apiserver.yaml
    kubectl apply -n ${VKS_NS} -f ${VKS_HOME}/manifests/kube-apiserver-service.yaml
}

update_kubeconfig() {
    IP=$1
    PORT=$2
    CURRENT_SERVER=$(cat ${VKS_HOME}/admin.conf | grep server: | awk '{print $2}')
    sed -i.bak "s|${CURRENT_SERVER}|https://${IP}:${PORT}|g" ${VKS_HOME}/admin.conf
    rm ${VKS_HOME}/admin.conf.bak
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
    kubeadm --kubeconfig=${VKS_HOME}/admin.conf init phase upload-config kubeadm 2>/dev/null
    kubectl --kubeconfig=${VKS_HOME}/admin.conf -n kube-system get configmap kubeadm-config \
        -o jsonpath='{.data.ClusterConfiguration}' > ${VKS_HOME}/kubeadm.yaml
}

create_cm_secret() {
    CURRENT_SERVER=$(cat ${VKS_HOME}/controller-manager.conf | grep server: | awk '{print $2}')
    sed -i.bak "s|${CURRENT_SERVER}|https://${VKS_NAME}:${API_SERVER_PORT}|g" ${VKS_HOME}/controller-manager.conf 
    rm ${VKS_HOME}/controller-manager.conf.bak 
    kubectl -n ${VKS_NS} delete secret cm-kubeconfig &>/dev/null
    kubectl -n ${VKS_NS} create secret generic cm-kubeconfig \
        --from-file=${VKS_HOME}/controller-manager.conf 
}

create_kubeconfig_secret() {
    IP=$1
    if [ "$2" != "" ]; then
        IP=$2
        echo "using external IP ${IP} for kubeconfig_secret"
    fi    
    CURRENT_SERVER=$(cat ${VKS_HOME}/admin.conf | grep server: | awk '{print $2}')
    sed "s|${CURRENT_SERVER}|https://${IP}:${KIND_CLUSTER_NODEPORT}|g; \
         s|kubernetes-admin@kubernetes|${VKS_NAME}|g; \
         s|kubernetes|${VKS_NAME}|g" \
         ${VKS_HOME}/admin.conf > ${VKS_HOME}/admin.kubeconfig 
    kubectl -n ${VKS_NS} delete secret admin-kubeconfig &>/dev/null
    kubectl -n ${VKS_NS} create secret generic admin-kubeconfig \
        --from-file=${VKS_HOME}/admin.kubeconfig 
}

apply_cm_manifests() {
    kubectl apply -n ${VKS_NS} -f ${VKS_HOME}/manifests/kube-controller-manager.yaml
}

create_bootstrap_token() {
kubectl get secrets --kubeconfig=${VKS_HOME}/admin.conf -n kube-system | grep bootstrap-token &>/dev/null
if [ "$?" -eq 0 ]; then
    echo "Bootstrap token found, skipping generation"
    return
fi
echo "Generating new boostrap token"
TOKEN_ID=$(openssl rand -hex 3)
TOKEN_SECRET=$(openssl rand -hex 8)
TOKEN=$TOKEN_ID.$TOKEN_SECRET

cat <<EOF | kubectl apply --kubeconfig=${VKS_HOME}/admin.conf -f -
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-$TOKEN_ID
  namespace: kube-system
type: bootstrap.kubernetes.io/token
stringData:
  description: "The default bootstrap token."
  token-id: $TOKEN_ID
  token-secret: $TOKEN_SECRET
  expiration: 2022-12-05T12:00:00Z
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"
  auth-extra-groups: system:bootstrappers:worker,system:bootstrappers:ingress
EOF
}

generate_cluster_info() {
  if [ "$2" != "" ]; then 
    IP=$2
  else
    IP=$1
  fi    
  kubectl -n kube-public --kubeconfig=${VKS_HOME}/admin.conf get configmap cluster-info &>/dev/null
  if [ "$?" -eq 0 ]; then
    echo "Cluster info found, re-creating"
    kubectl -n kube-public --kubeconfig=${VKS_HOME}/admin.conf create configmap cluster-info
    return
  fi
  echo "Generating new cluster info"
  kubectl config set-cluster bootstrap \
  --kubeconfig=${VKS_HOME}/bootstrap-kubeconfig-public  \
  --server=https://${IP}:${KIND_CLUSTER_NODEPORT}\
  --certificate-authority=${VKS_HOME}/pki/ca.crt \
  --embed-certs=true

  kubectl -n kube-public --kubeconfig=${VKS_HOME}/admin.conf create configmap cluster-info \
  --from-file=kubeconfig=${VKS_HOME}/bootstrap-kubeconfig-public 
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

create_certs ${CLUSTER_IP} ${externalIP}

create_vks_ns

create_vksdb_ns

install_db

DB_PASSWORD=$(get_db_password)

create_or_update_certs_secret

configure_manifests ${DB_PASSWORD}

apply_manifests

update_kubeconfig ${VKS_NAME}.${VKS_NS}.svc ${API_SERVER_PORT}

check_vks_up

upload_kubeadm_config

create_cm_secret

create_kubeconfig_secret ${CLUSTER_IP} ${externalIP}

apply_cm_manifests

create_bootstrap_token

generate_cluster_info ${CLUSTER_IP} ${externalIP}