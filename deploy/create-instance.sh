#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

${SCRIPT_DIR}/vks/create-vks.sh $1

${SCRIPT_DIR}/ocm/deploy-cluster-manager.sh $1
