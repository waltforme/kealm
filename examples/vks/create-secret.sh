#!/bin/sh

CERTS_PATH=/etc/kubernetes/pki
KC_PATH=/etc/kubernetes

kubectl create secret generic k8s-certs \
  --from-file=${CERTS_PATH}/ca.crt \
  --from-file=${CERTS_PATH}/ca.key \
  --from-file=${CERTS_PATH}/apiserver-kubelet-client.crt \
  --from-file=${CERTS_PATH}/apiserver-kubelet-client.key \
  --from-file=${CERTS_PATH}/front-proxy-client.crt \
  --from-file=${CERTS_PATH}/front-proxy-client.key \
  --from-file=${CERTS_PATH}/front-proxy-ca.crt \
  --from-file=${CERTS_PATH}/sa.pub \
  --from-file=${CERTS_PATH}/sa.key \
  --from-file=${CERTS_PATH}/apiserver.crt \
  --from-file=${CERTS_PATH}/apiserver.key

kubectl create secret generic cm-kubeconfig \
     --from-file=${KC_PATH}/controller-manager.conf

# TMP_DIR=$(mktemp -d -t cmkc-XXXXXXXXXX)
# sed "s\API_SERVER_URL\https://ip-172-31-37-22:7443\g" ${KC_PATH}/controller-manager.conf > ${TMP_DIR}/controller-manager.conf
# kubectl create secret generic cm-kubeconfig \
#     --from-file=${TMP_DIR}/controller-manager.conf
# rm -rf ${TMP_DIR}   
