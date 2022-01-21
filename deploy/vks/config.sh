#!/bin/bash

PROJECT_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/../.. && pwd )"

USE_KIND="${USE_KIND:-true}"

VKS_NAME="${VKS_NAME:-vks1}"
VKS_HOME=${PROJECT_HOME}/.${VKS_NAME}
DB_RELEASE_NAME=mypsql
VKS_NS=${VKS_NAME}-system
KIND_CLUSTER_NAME=vkshost

# TODO - temporary hack for limitation with nodeports on kind
if [ "$VKS_NAME" == "vks1" ]; then
    KIND_CLUSTER_NODEPORT=31433
    API_SERVER_PORT=7443
elif [ "$VKS_NAME" == "vks2" ]; then
    KIND_CLUSTER_NODEPORT=31434
    API_SERVER_PORT=7444
elif [ "$VKS_NAME" == "vks3" ]; then
    KIND_CLUSTER_NODEPORT=31435
    API_SERVER_PORT=7445
else
    echo "name must be one of {'vks1','vks2','vks3'}"
    exit -127    
fi        

