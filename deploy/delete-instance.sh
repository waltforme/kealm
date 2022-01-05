#!/bin/bash

PROJECT_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"

source ${PROJECT_HOME}/deploy/vks/config.sh

###############################################################################################
#               Functions
###############################################################################################


delete_db() {
    helm delete --namespace ${VKS_NS} ${DB_RELEASE_NAME} 
}


delete_all() {
    kubectl delete -n ${VKS_NS} deployments --all
    kubectl delete -n ${VKS_NS} cm --all
    kubectl delete -n ${VKS_NS} secrets --all
    kubectl delete ns ${VKS_NS}
}

delete_dir() {
    rm -rf ${VKS_HOME}
}


###########################################################################################
#                   Main   
###########################################################################################

unset KUBECONFIG

delete_db

delete_all

delete_dir

