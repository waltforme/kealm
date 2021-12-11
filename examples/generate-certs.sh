#!/bin/sh

CERTS_DIR=certs

mkdir -p ${CERTS_DIR}

# Generate self signed root CA cert
openssl req -nodes -x509 -newkey \
    rsa:2048 -keyout ${CERTS_DIR}/ca.key -out ${CERTS_DIR}/ca.crt  \
    -subj "/C=AU/ST=VIC/L=Melbourne/O=Ranch/OU=root/CN=root/emailAddress=sample@sample.com"

# Generate server cert to be signed
openssl req -newkey rsa:2048 -nodes \
  -keyout ${CERTS_DIR}/server.key -out ${CERTS_DIR}/server.csr \
  -config req.conf

# Sign the server cert
openssl x509 -extfile req.conf  -extensions req_ext \
    -req -in ${CERTS_DIR}/server.csr -CA ${CERTS_DIR}/ca.crt -CAkey ${CERTS_DIR}/ca.key -CAcreateserial -out ${CERTS_DIR}/server.crt

# change permission of .key files so that can be accessed by the process in docker
chmod 664 ${CERTS_DIR}/*.key

openssl x509 -in ${CERTS_DIR}/server.crt -noout -text