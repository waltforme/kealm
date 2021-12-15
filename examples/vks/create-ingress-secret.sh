#!/bin/sh

CERTS_PATH=/etc/kubernetes/pki

kubectl create secret generic ca-secret \
   --from-file=tls.crt=${CERTS_PATH}/apiserver.crt \
   --from-file=tls.key=${CERTS_PATH}/apiserver.key \
   --from-file=ca.crt=${CERTS_PATH}/ca.crt