FROM registry.access.redhat.com/ubi8/ubi-minimal:latest

RUN  microdnf update && microdnf install -y jq openssl tar gzip util-linux

RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" &&\
    chmod a+x kubectl &&\
    mv kubectl /usr/local/bin &&\
    curl -LO --remote-name-all "https://storage.googleapis.com/kubernetes-release/release/$(curl -sSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubeadm" &&\
    chmod a+x kubeadm &&\
    mv kubeadm /usr/local/bin &&\
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

COPY deploy/ deploy/

ENV USER_UID=10001