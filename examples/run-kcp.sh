#!/bin/sh

KCP_CMD=/home/ubuntu/go/src/github.com/kcp-dev/kcp/bin/kcp

CERTS_DIR=certs
PASSWORD=dummy-pw
CURRENT_DIR="$(pwd)"
DEMO_ROOT="$(cd $(dirname "${BASH_SOURCE}") && pwd)"

docker rm -f kine-mysql

docker run --name kine-mysql -v $CURRENT_DIR/$CERTS_DIR:/etc/mysql/conf.d -p 3306:3306 -e MYSQL_DATABASE=kine -e MYSQL_ROOT_PASSWORD=$PASSWORD -d mysql:latest

echo "waiting for DB to start..."
sleep 20

kine --endpoint "mysql://root:$PASSWORD@tcp(localhost:3306)/kine"  --ca-file ${CERTS_DIR}/ca.crt --cert-file ${CERTS_DIR}/server.crt --key-file ${CERTS_DIR}/server.key --server-cert-file ${CERTS_DIR}/server.crt --server-key-file ${CERTS_DIR}/server.key &> kcp.log &
KINE_PID=$!
echo "KINE started: $KINE_PID" 

${KCP_CMD} start --etcd-servers  https://127.0.0.1:2379 --etcd-cafile ${CERTS_DIR}/ca.crt --etcd-certfile ${CERTS_DIR}/server.crt --etcd-keyfile ${CERTS_DIR}/server.key


