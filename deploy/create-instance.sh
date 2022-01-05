#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

${SCRIPT_DIR}/vks/create-vks.sh

${SCRIPT_DIR}/ocm/deploy-cluster-manager.sh
